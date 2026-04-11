import Foundation
import Observation
import AVFoundation
import AVKit

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
    let id: Int
    let name: String
    let codec: String
    let language: String?
    let isDefault: Bool
}

/// AVFoundation-backed video player engine.
///
/// This is a thin wrapper around `AVPlayer` + `AVPlayerItem`. The actual
/// player UI (transport bar, scrubbing, audio/subtitle picker, info
/// overlay) is provided by `AVPlayerViewController` — we don't render
/// any of that ourselves. The engine just exposes the state our
/// PlayerViewModel needs (currentTime, duration, isPlaying, error).
///
/// Why AVPlayer:
/// - Apple-native, supported by every Apple TV / tvOS version
/// - Hardware-accelerated H.264 / HEVC / HDR10 / Dolby Vision out of the box
/// - AC3 / EAC3 / Atmos passthrough automatic
/// - Native AVPlayerViewController gives us the real tvOS player UX,
///   including Siri Remote scrubbing, audio/subtitle picker, info overlay,
///   PiP, AirPlay — all things we'd otherwise have to build ourselves
/// - AFR (frame rate matching) handled automatically by the system
/// - Gets fixes / improvements with every tvOS release for free
///
/// Codecs / containers AVPlayer doesn't handle (DTS, TrueHD, AV1, MKV,
/// VC1, MPEG2) are translated server-side by Jellyfin: MKV is remuxed
/// to fragmented MP4 / HLS without re-encoding, exotic codecs are
/// transcoded. See `DirectPlayProfile.swift`.
@Observable
@MainActor
final class AVPlayerEngine {
    // MARK: - Public State

    var state: EngineState = .idle
    var currentTime: Double = 0
    var duration: Double = 0
    var progress: Float = 0
    var audioTracks: [TrackInfo] = []
    var subtitleTracks: [TrackInfo] = []
    var currentAudioTrackIndex: Int = -1
    var currentSubtitleTrackIndex: Int = -1

    /// The underlying AVPlayer. Handed to AVPlayerViewController via
    /// NativeVideoPlayerView.
    let player = AVPlayer()

    // MARK: - Private

    private var playerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var pendingStartPosition: Double?

    init() {
        // AVPlayer expects an active audio session for tvOS playback.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("[AVPlayer] AVAudioSession error: \(error)")
            #endif
        }

        // Periodic time observer drives currentTime / progress updates.
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            // The closure is delivered to .main; hop to MainActor explicitly.
            MainActor.assumeIsolated {
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if self.duration > 0 {
                    self.progress = Float(self.currentTime / self.duration)
                }
            }
        }
    }

    // No deinit cleanup: under Swift 6 strict concurrency, deinit is
    // nonisolated and can't touch main-actor properties. Cleanup happens
    // in stop() instead, which the PlayerViewModel calls on dismiss.

    // MARK: - Public API

    /// Load a media URL. Replaces any current playback.
    /// `isHDR` should be true if the source video is HDR10/HLG/DV — caller
    /// reads that from Jellyfin's media stream metadata. We use it to
    /// install the HDR passthrough compositor *before* `play()`, so the
    /// frame production path is wired correctly from the very first frame
    /// instead of trying to attach it asynchronously after the broken HLS
    /// pipeline already wedged.
    func load(url: URL, startPosition: Double? = nil, isHDR: Bool = false) async throws {
        state = .loading
        currentTime = 0
        duration = 0
        progress = 0
        audioTracks = []
        subtitleTracks = []
        currentAudioTrackIndex = -1
        currentSubtitleTrackIndex = -1
        pendingStartPosition = (startPosition ?? 0) > 0 ? startPosition : nil

        #if DEBUG
        print("[AVPlayer] Loading: \(url.absoluteString)")
        #endif

        // Tear down previous item observers
        statusObserver?.invalidate()
        timeControlObserver?.invalidate()
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }

        // Don't let AVFoundation auto-pick a closed-caption / subtitle
        // track from the HLS playlist. Jellyfin's HLS often advertises a
        // CC track tagged accessibility.transcribes-spoken-dialog with
        // default=YES, which AVPlayerViewController complains about
        // ("Received a non-forced-only media selection ... when display
        // type was forced-only"). The user can still enable subs from
        // the system overlay.
        player.appliesMediaSelectionCriteriaAutomatically = false

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        playerItem = item

        if isHDR {
            // Display-aware HDR handling:
            // - HDR-capable display + Match Dynamic Range on → AVPlayer's
            //   native HDR direct play. No compositor, no tone mapping,
            //   pixel-perfect HDR10 / Dolby Vision.
            // - SDR display, OR HDR display with Match Dynamic Range off
            //   → install our Metal HDR→SDR compositor (BT.2390 in PQ
            //   space) so the broken AVPlayer EDR display path is
            //   bypassed entirely.
            if DisplayCapabilities.supportsHDR {
                #if DEBUG
                print("[AVPlayer] HDR source + HDR display → native HDR direct play")
                #endif
                // Default appliesPerFrameHDRDisplayMetadata = true is correct
                // for native DV / HDR10 on an HDR-capable system.
            } else {
                #if DEBUG
                print("[AVPlayer] HDR source + SDR display → installing Metal HDR→SDR compositor (BT.2390)")
                #endif
                // Disable per-frame DV RPU processing — that's the operation
                // that hangs the AVPlayer pipeline. Without it, AVFoundation
                // hands us the HDR10 base layer (PQ encoded) which our Metal
                // compositor can tone-map.
                item.appliesPerFrameHDRDisplayMetadata = false
                item.videoComposition = makeHDRToSDRComposition()
            }
        }

        // Observe item status — fires when ready to play or fails
        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleItemStatus(item.status, item: item)
            }
        }

        // Observe player time control status (playing / paused / waiting)
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleTimeControlStatus(player.timeControlStatus)
            }
        }

        // End-of-playback notification
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.state = .idle
            }
        }

        player.replaceCurrentItem(with: item)
        player.play()
    }

    func play() {
        player.play()
        state = .playing
    }

    func pause() {
        player.pause()
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
        let target = max(0, seconds)
        state = .seeking
        #if DEBUG
        print("[AVPlayer] Seek to \(String(format: "%.1f", target))s")
        #endif
        let time = CMTime(seconds: target, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        // After the seek completes, timeControlStatus will fire .playing /
        // .paused and we move out of .seeking from there.
        if player.timeControlStatus == .playing {
            state = .playing
        } else if player.rate == 0 {
            state = .paused
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
        currentTime = 0
        progress = 0

        // Drop the time observer + notification observer so AVPlayer can
        // be released cleanly. (deinit can't do this under Swift 6.)
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }

    func selectAudioTrack(index: Int) async {
        guard let item = playerItem else { return }
        await selectMediaOption(in: item, characteristic: .audible, trackID: index)
        currentAudioTrackIndex = index
    }

    func selectSubtitleTrack(index: Int) async {
        guard let item = playerItem else { return }
        await selectMediaOption(in: item, characteristic: .legible, trackID: index)
        currentSubtitleTrackIndex = index
    }

    // MARK: - Item Status Handling

    private func handleItemStatus(_ status: AVPlayerItem.Status, item: AVPlayerItem) {
        switch status {
        case .readyToPlay:
            #if DEBUG
            print("[AVPlayer] Item ready")
            #endif
            // Pull duration
            let dur = item.duration.seconds
            if dur.isFinite, dur > 0 {
                duration = dur
            }
            // Apply pending start position
            if let start = pendingStartPosition, start > 0 {
                let time = CMTime(seconds: start, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                Task {
                    await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                }
                pendingStartPosition = nil
            }
            Task {
                await fetchTrackList(item: item)
            }

        case .failed:
            let msg = item.error?.localizedDescription ?? "Unknown playback error"
            #if DEBUG
            print("[AVPlayer] Item failed: \(msg)")
            #endif
            state = .error(msg)

        case .unknown:
            break

        @unknown default:
            break
        }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        // Don't override .seeking — seek() handles its own state transition.
        if case .seeking = state { return }

        switch status {
        case .playing:
            state = .playing
        case .paused:
            // Distinguish "user paused" from "idle / no item"
            if player.currentItem == nil {
                state = .idle
            } else {
                state = .paused
            }
        case .waitingToPlayAtSpecifiedRate:
            // Buffering — keep showing spinner only on initial load
            if duration == 0 {
                state = .loading
            }
        @unknown default:
            break
        }
    }

    // MARK: - HDR → SDR (Metal compute shader compositor)

    /// Build a video composition that runs every HDR frame through our
    /// custom Metal compositor (`HDRToneMappingCompositor`).
    ///
    /// We don't await `asset.loadTracks(...)` here — that's the call that
    /// hangs on HDR HLS streams. We build the composition with sane
    /// defaults and a single open-ended instruction that covers the
    /// entire (unknown) asset duration. AVFoundation does the
    /// per-frame routing.
    private func makeHDRToSDRComposition() -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = HDRToneMappingCompositor.self
        composition.renderSize = CGSize(width: 3840, height: 2160)
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        // Output color space marker — BT.709 SDR
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        // A custom video compositor needs at least one instruction
        // covering the asset's time range, otherwise AVFoundation
        // rejects the composition with Fig -12710 (FormatNotSupported)
        // before the first frame ever reaches us. Use a positive-infinity
        // duration so we don't have to load the asset duration up front.
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(value: .max, timescale: 30000)
        )
        instruction.enablePostProcessing = true
        composition.instructions = [instruction]
        return composition
    }

    // MARK: - Track List

    private func fetchTrackList(item: AVPlayerItem) async {
        var audio: [TrackInfo] = []
        var subs: [TrackInfo] = []
        var selectedAudio = -1
        var selectedSub = -1

        // Audio tracks
        if let audioGroup = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
            let selected = item.currentMediaSelection.selectedMediaOption(in: audioGroup)
            for (idx, option) in audioGroup.options.enumerated() {
                let info = TrackInfo(
                    id: idx,
                    name: option.displayName,
                    codec: option.mediaType.rawValue,
                    language: option.extendedLanguageTag,
                    isDefault: false
                )
                audio.append(info)
                if option == selected { selectedAudio = idx }
            }
        }

        // Subtitle / closed-caption tracks
        if let subGroup = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
            let selected = item.currentMediaSelection.selectedMediaOption(in: subGroup)
            for (idx, option) in subGroup.options.enumerated() {
                let info = TrackInfo(
                    id: idx,
                    name: option.displayName,
                    codec: option.mediaType.rawValue,
                    language: option.extendedLanguageTag,
                    isDefault: false
                )
                subs.append(info)
                if option == selected { selectedSub = idx }
            }
        }

        self.audioTracks = audio
        self.subtitleTracks = subs
        self.currentAudioTrackIndex = selectedAudio
        self.currentSubtitleTrackIndex = selectedSub

        #if DEBUG
        print("[AVPlayer] Tracks: \(audio.count) audio, \(subs.count) subs")
        #endif
    }

    private func selectMediaOption(
        in item: AVPlayerItem,
        characteristic: AVMediaCharacteristic,
        trackID: Int
    ) async {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic) else {
            return
        }
        if trackID < 0 {
            // Disable
            item.select(nil, in: group)
        } else if trackID < group.options.count {
            item.select(group.options[trackID], in: group)
        }
    }
}
