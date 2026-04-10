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
///
/// IMPORTANT: this engine does NOT own the VLCMediaPlayer. The
/// VLCContainerView (UIView) creates the player together with its drawable
/// subview in the same synchronous init — that's the supported tvOS
/// pattern (matches Swiftfin / VLCUI). The view then calls `bind(player:)`
/// to hand the player back to us.
///
/// Until `bind()` runs, calls to `load(url:)` are queued and replayed.
@Observable
@MainActor
final class VLCPlayerEngine {
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

    private weak var player: VLCMediaPlayer?
    private var pendingStartPosition: Double?
    private var pendingLoad: (url: URL, startPosition: Double?)?
    private var hasFetchedTracksForCurrentMedia = false

    init() {}

    // MARK: - Bind from view

    /// Called by VLCContainerView once the player and its drawable are set
    /// up. Replays any load() that came in before the view was attached.
    func bind(player: VLCMediaPlayer) {
        self.player = player

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

        #if DEBUG
        print("[VLC] Engine bound to player")
        #endif

        if let pending = pendingLoad {
            pendingLoad = nil
            performLoad(url: pending.url, startPosition: pending.startPosition)
        }
    }

    // MARK: - Public API

    /// Load a media URL. Replaces any current playback.
    func load(url: URL, startPosition: Double? = nil) async throws {
        guard player != nil else {
            // View hasn't bound yet — queue and let bind() replay it
            pendingLoad = (url, startPosition)
            #if DEBUG
            print("[VLC] load() queued (player not yet bound)")
            #endif
            return
        }
        performLoad(url: url, startPosition: startPosition)
    }

    private func performLoad(url: URL, startPosition: Double?) {
        guard let player = player else { return }

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

        // No media options — VLC defaults are correct on tvOS, and Swiftfin
        // / VLCUI runs with no options too.
        let media = VLCMedia(url: url)
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
        player.currentAudioTrackIndex = Int32(index)
        currentAudioTrackIndex = index
    }

    func selectSubtitleTrack(index: Int) async {
        guard let player = player else { return }
        player.currentVideoSubTitleIndex = Int32(index)
        currentSubtitleTrackIndex = index
    }

    // MARK: - Delegate Callbacks (called from VLCContainerView on main actor)

    /// Called from VLCContainerView's mediaPlayerStateChanged delegate.
    func handleStateChanged(state vlcState: VLCMediaPlayerState) {
        guard let player = player else { return }

        #if DEBUG
        print("[VLC] state=\(vlcStateName(vlcState))")
        #endif

        switch vlcState {
        case .opening, .buffering:
            if case .seeking = self.state { return }
            self.state = .loading

        case .playing:
            // First playing event after a load: apply pending startPosition + grab tracks
            if let start = pendingStartPosition, start > 0 {
                player.time = VLCTime(int: Int32(start * 1000))
                pendingStartPosition = nil
            }
            self.state = .playing
            fetchTrackListIfReady()

        case .paused:
            self.state = .paused

        case .stopped, .ended:
            self.state = .idle

        case .error:
            self.state = .error("VLC playback error")

        case .esAdded:
            // New elementary stream — refresh tracks
            hasFetchedTracksForCurrentMedia = false
            fetchTrackListIfReady()

        @unknown default:
            break
        }
    }

    /// Called from VLCContainerView's mediaPlayerTimeChanged delegate.
    func handleTimeChanged(timeMs: Int32, lengthMs: Int32) {
        currentTime = Double(timeMs) / 1000.0
        if lengthMs > 0 {
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

    // MARK: - Track List

    private func fetchTrackListIfReady() {
        guard !hasFetchedTracksForCurrentMedia, let player = player else { return }
        let audioIndexes = (player.audioTrackIndexes as? [NSNumber]) ?? []
        guard !audioIndexes.isEmpty || player.numberOfSubtitlesTracks > 0 else { return }

        let audioNames = (player.audioTrackNames as? [String]) ?? []
        var audio: [TrackInfo] = []
        for (i, idNum) in audioIndexes.enumerated() {
            let id = idNum.intValue
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

    private func vlcStateName(_ state: VLCMediaPlayerState) -> String {
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

    var errorDescription: String? {
        switch self {
        case .notInitialized: "VLC player not initialized"
        }
    }
}
