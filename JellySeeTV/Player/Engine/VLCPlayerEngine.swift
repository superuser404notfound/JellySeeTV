import Foundation
import Observation
import UIKit
import AVFoundation
import VLCKitSPM

/// The state of the player engine
enum EngineState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case seeking
    case error(String)
}

/// Info about an audio or subtitle track
struct TrackInfo: Identifiable, Sendable, Equatable {
    /// VLC track id (matches `currentAudioTrackIndex` / `currentVideoSubTitleIndex`)
    let id: Int
    let name: String
    let codec: String
    let language: String?
    let isDefault: Bool
}

/// VLCKit-backed video player engine.
/// libvlc handles demuxing, decoding (VideoToolbox HW), audio output via
/// AVAudioSession + AudioQueue, A/V sync, seeking, subtitles, and HDR.
/// We render into a plain UIView that we pass as `drawable`.
@Observable
@MainActor
final class VLCPlayerEngine: NSObject {
    // MARK: - Public State

    var state: EngineState = .idle
    var currentTime: Double = 0
    var duration: Double = 0
    var progress: Float = 0
    var audioTracks: [TrackInfo] = []
    var subtitleTracks: [TrackInfo] = []
    var currentAudioTrackIndex: Int = -1
    var currentSubtitleTrackIndex: Int = -1

    // MARK: - Private

    private var player: VLCMediaPlayer?
    private var pendingStartPosition: Double?
    private var hasFetchedTracksForCurrentMedia = false
    /// Drawable handed to us by VideoLayerView once it has a real
    /// view-hierarchy + Auto Layout constraints.
    private weak var drawableView: UIView?

    override init() {
        super.init()
    }

    deinit {
        // VLCMediaPlayer cleanup happens automatically when reference drops
    }

    // MARK: - Drawable

    /// Called by VideoLayerView once the drawable subview is in the
    /// view hierarchy with Auto Layout constraints. Wires it through to
    /// VLC, creating the player on first call if needed.
    func attachDrawable(_ view: UIView) {
        drawableView = view
        if let player = player {
            player.drawable = view
        }
    }

    // MARK: - Initialization

    private func ensurePlayer() {
        guard player == nil else { return }

        // Activate AVAudioSession (VLC's audio output goes through it on tvOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[VLC] AVAudioSession error: \(error)")
            #endif
        }

        // IMPORTANT: do NOT pass options to VLCMediaPlayer's init.
        // VLCMediaPlayer(options:) spawns a *private libvlc instance* with
        // its own video-output thread setup, which on tvOS breaks the
        // OpenGLES2 video view (it ends up calling -doResetBuffers off the
        // main thread, the render pipeline wedges, and playback stays in
        // an infinite buffering loop). The shared default libvlc instance
        // sets the vout up correctly. Per-stream tunables (HW decode,
        // network cache) are applied as VLCMedia options instead — see load().
        let p = VLCMediaPlayer()
        p.delegate = self
        if let drawable = drawableView {
            p.drawable = drawable
        }
        player = p

        #if DEBUG
        print("[VLC] Initialized (drawable=\(drawableView != nil ? "set" : "pending"))")
        #endif
    }

    // MARK: - Public API

    /// Load a media URL. Replaces any current playback.
    func load(url: URL, startPosition: Double? = nil) async throws {
        ensurePlayer()
        guard let player = player else {
            throw VLCEngineError.notInitialized
        }

        state = .loading
        currentTime = 0
        duration = 0
        progress = 0
        audioTracks = []
        subtitleTracks = []
        currentAudioTrackIndex = -1
        currentSubtitleTrackIndex = -1
        hasFetchedTracksForCurrentMedia = false
        pendingStartPosition = (startPosition ?? 0) > 0 ? startPosition : nil

        #if DEBUG
        print("[VLC] Loading: \(url.absoluteString)")
        #endif

        let media = VLCMedia(url: url)
        // Per-stream options live on the media object, not the player.
        // network-caching is in milliseconds; VLC's HTTP reader uses it as
        // its read-ahead buffer, which keeps long-form direct play smooth.
        media.addOption(":network-caching=1500")
        media.addOption(":http-reconnect")
        media.addOption(":avcodec-hw=videotoolbox")
        media.addOption(":no-osd")

        player.media = media
        player.play()
    }

    func play() {
        guard let player = player else { return }
        player.play()
        state = .playing
    }

    func pause() {
        guard let player = player else { return }
        if player.canPause {
            player.pause()
        }
        state = .paused
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused: play()
        default: break
        }
    }

    func seek(to seconds: Double) async {
        guard let player = player else { return }
        let target = max(0, seconds)
        state = .seeking
        #if DEBUG
        print("[VLC] Seek to \(String(format: "%.1f", target))s")
        #endif
        // VLCTime takes milliseconds as Int32
        player.time = VLCTime(int: Int32(target * 1000))
    }

    func stop() {
        guard let player = player else { return }
        player.stop()
        state = .idle
        currentTime = 0
        progress = 0
    }

    func selectAudioTrack(index: Int) async {
        guard let player = player else { return }
        // VLCMediaPlayer uses -1 for "disabled" / no audio track
        player.currentAudioTrackIndex = Int32(index)
        currentAudioTrackIndex = index
    }

    func selectSubtitleTrack(index: Int) async {
        guard let player = player else { return }
        // VLCMediaPlayer uses -1 for "disabled" / no subtitle
        player.currentVideoSubTitleIndex = Int32(index)
        currentSubtitleTrackIndex = index
    }

    // MARK: - Track List

    private func fetchTrackListIfReady() {
        guard !hasFetchedTracksForCurrentMedia, let player = player else { return }
        // VLCKit only knows the track lists once playback has actually started
        // and the demuxer reported them. audioTrackIndexes is empty until then.
        let audioIndexes = (player.audioTrackIndexes as? [NSNumber]) ?? []
        guard !audioIndexes.isEmpty || player.numberOfSubtitlesTracks > 0 else { return }

        let audioNames = (player.audioTrackNames as? [String]) ?? []
        var audio: [TrackInfo] = []
        for (i, idNum) in audioIndexes.enumerated() {
            let id = idNum.intValue
            // VLC reports id == -1 for the "Disable" pseudo-track — skip it
            guard id >= 0 else { continue }
            let name = i < audioNames.count ? audioNames[i] : "Audio \(id)"
            audio.append(TrackInfo(
                id: id,
                name: name,
                codec: "",
                language: nil,
                isDefault: false
            ))
        }

        let subIndexes = (player.videoSubTitlesIndexes as? [NSNumber]) ?? []
        let subNames = (player.videoSubTitlesNames as? [String]) ?? []
        var subs: [TrackInfo] = []
        for (i, idNum) in subIndexes.enumerated() {
            let id = idNum.intValue
            guard id >= 0 else { continue }
            let name = i < subNames.count ? subNames[i] : "Subtitle \(id)"
            subs.append(TrackInfo(
                id: id,
                name: name,
                codec: "",
                language: nil,
                isDefault: false
            ))
        }

        self.audioTracks = audio
        self.subtitleTracks = subs
        self.currentAudioTrackIndex = Int(player.currentAudioTrackIndex)
        self.currentSubtitleTrackIndex = Int(player.currentVideoSubTitleIndex)
        self.hasFetchedTracksForCurrentMedia = true

        #if DEBUG
        print("[VLC] Tracks: \(audio.count) audio, \(subs.count) subs")
        #endif
    }
}

// MARK: - VLCMediaPlayerDelegate

extension VLCPlayerEngine: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        // VLC delegate fires from a libvlc background thread — bounce to main
        Task { @MainActor [weak self] in
            self?.handleStateChanged()
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleTimeChanged()
        }
    }

    @MainActor
    private func handleStateChanged() {
        guard let player = player else { return }
        let vlcState = player.state

        #if DEBUG
        print("[VLC] state=\(vlcStateName(vlcState))")
        #endif

        switch vlcState {
        case .opening, .buffering:
            if case .seeking = state { return }
            state = .loading

        case .playing:
            // First playing event after a load: apply pending startPosition + grab tracks
            if let start = pendingStartPosition, start > 0 {
                player.time = VLCTime(int: Int32(start * 1000))
                pendingStartPosition = nil
            }
            state = .playing
            fetchTrackListIfReady()

        case .paused:
            state = .paused

        case .stopped, .ended:
            state = .idle

        case .error:
            state = .error("VLC playback error")

        case .esAdded:
            // New elementary stream — refresh tracks
            hasFetchedTracksForCurrentMedia = false
            fetchTrackListIfReady()

        @unknown default:
            break
        }
    }

    @MainActor
    private func handleTimeChanged() {
        guard let player = player else { return }
        // VLCTime.intValue is Int32 milliseconds
        let ms = player.time.intValue
        currentTime = Double(ms) / 1000.0

        // Duration may not be known until after first frame; refresh on every tick
        if let lengthMs = player.media?.length.intValue, lengthMs > 0 {
            duration = Double(lengthMs) / 1000.0
        }
        if duration > 0 {
            progress = Float(currentTime / duration)
        }

        // Late-bind track list if VLC reported them after first frames
        if !hasFetchedTracksForCurrentMedia {
            fetchTrackListIfReady()
        }
    }

    private nonisolated func vlcStateName(_ state: VLCMediaPlayerState) -> String {
        switch state {
        case .stopped: return "stopped"
        case .opening: return "opening"
        case .buffering: return "buffering"
        case .ended: return "ended"
        case .error: return "error"
        case .playing: return "playing"
        case .paused: return "paused"
        case .esAdded: return "esAdded"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Errors

enum VLCEngineError: LocalizedError {
    case notInitialized
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized: "VLC player not initialized"
        case .loadFailed(let msg): "Failed to load media: \(msg)"
        }
    }
}
