import Foundation
import Observation

/// ViewModel that bridges the AVPlayer engine with Jellyfin session
/// reporting and our custom tvOS-style player UI.
///
/// Owns the entire player UI state because we no longer use
/// AVPlayerViewController — the Metal HDR renderer renders the video into
/// a CAMetalLayer, and we lay our own SwiftUI controls (TransportBar,
/// scrubbing, etc.) on top.
@Observable
@MainActor
final class PlayerViewModel {
    var isLoading = true
    var errorMessage: String?
    var isPlaying = false
    var showControls = false
    var currentTime: String = "00:00"
    var totalTime: String = "00:00"
    var remainingTime: String = "-00:00"
    var progress: Float = 0

    // Scrubbing state
    var isScrubbing = false
    var scrubProgress: Float = 0
    var scrubTime: String = "00:00"
    /// True if the user actually moved the scrub position (not just touched briefly)
    var didMoveScrub = false
    /// Progress shown on the bar: scrub position during scrub, live position otherwise
    var displayedProgress: Float { isScrubbing ? scrubProgress : progress }
    private var scrubStartTime: Double = 0

    let item: JellyfinItem
    let engine = AVPlayerEngine()

    private let playbackService: JellyfinPlaybackServiceProtocol
    private let userID: String
    private let startFromBeginning: Bool
    private var cachedPlaybackInfo: PlaybackInfoResponse?
    private var progressTimer: Task<Void, Never>?
    private var controlsTimer: Task<Void, Never>?
    private var stateObserver: Task<Void, Never>?
    private var hasReportedStart = false
    private var hasStartedPlaying = false
    private var mediaSourceID: String = ""
    private var playSessionID: String?

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String, cachedPlaybackInfo: PlaybackInfoResponse? = nil) {
        self.item = item
        self.startFromBeginning = startFromBeginning
        self.playbackService = playbackService
        self.userID = userID
        self.cachedPlaybackInfo = cachedPlaybackInfo
    }

    // MARK: - Lifecycle

    func startPlayback() async {
        isLoading = true
        errorMessage = nil

        do {
            // Get playback info (cached or fresh)
            let info: PlaybackInfoResponse
            if let cached = cachedPlaybackInfo {
                info = cached
            } else {
                info = try await playbackService.getPlaybackInfo(
                    itemID: item.id,
                    userID: userID,
                    profile: DirectPlayProfile.current()
                )
            }
            playSessionID = info.playSessionId

            guard let source = info.mediaSources.first else {
                throw PlayerEngineError.noSource
            }
            mediaSourceID = source.id

            // Pick the right URL based on what Jellyfin offered for this
            // source. The server already evaluated our DeviceProfile and
            // decided whether direct play, container remux (DirectStream),
            // or full transcode is needed.
            //
            // - If TranscodingUrl is set, the server has prepared an HLS
            //   playlist for us (typically /videos/<id>/main.m3u8). This
            //   handles MKV→fMP4 remuxing and any codec transcoding the
            //   source needs. AVPlayer can play HLS natively.
            // - Otherwise the source is direct-playable as-is, so we hit
            //   /Videos/<id>/stream.<container>?Static=true and AVPlayer
            //   reads the file straight from the server.
            let url: URL
            if let transcodePath = source.transcodingUrl, !transcodePath.isEmpty {
                guard let transcodeURL = playbackService.buildTranscodeURL(relativePath: transcodePath) else {
                    throw PlayerEngineError.noURL
                }
                url = transcodeURL
                #if DEBUG
                print("[PlayerViewModel] Using transcoded HLS path")
                #endif
            } else {
                guard let directURL = playbackService.buildStreamURL(
                    itemID: item.id,
                    mediaSourceID: source.id,
                    container: source.container,
                    isStatic: true
                ) else {
                    throw PlayerEngineError.noURL
                }
                url = directURL
                #if DEBUG
                print("[PlayerViewModel] Using direct stream")
                #endif
            }

            // Start position
            let startPos: Double? = if !startFromBeginning,
                let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
                ticks.ticksToSeconds
            } else {
                nil
            }

            // HDR detection from Jellyfin's media stream metadata. The
            // server already knows the source range — we don't have to
            // wait for AVPlayer to parse the HLS manifest (which is
            // exactly the operation that hangs on HDR streams). Possible
            // VideoRangeType values from Jellyfin: SDR, HDR, HDR10, DOVI,
            // HLG. Anything other than SDR triggers our HDR handling.
            let videoStream = source.mediaStreams?.first { $0.type == .video }
            let isHDR: Bool = {
                let range = videoStream?.videoRangeType ?? videoStream?.videoRange ?? "SDR"
                return range.uppercased() != "SDR"
            }()
            #if DEBUG
            print("[PlayerViewModel] Source range: \(videoStream?.videoRangeType ?? videoStream?.videoRange ?? "unknown") → isHDR=\(isHDR)")
            #endif

            try await engine.load(url: url, startPosition: startPos, isHDR: isHDR)

            startStateObserver()
            await reportStart()
            startProgressReporting()

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func stopPlayback() async {
        stopProgressReporting()
        stateObserver?.cancel()
        await reportStop()
        engine.stop()
    }

    // MARK: - Controls

    func togglePlayPause() {
        engine.togglePlayPause()
        showControls = true
        scheduleControlsHide()
    }

    func seekForward() {
        Task { await engine.seek(to: engine.currentTime + 10) }
        showControlsTemporarily()
    }

    func seekBackward() {
        Task { await engine.seek(to: engine.currentTime - 10) }
        showControlsTemporarily()
    }

    func selectAudioTrack(id: Int) {
        Task { await engine.selectAudioTrack(index: id) }
    }

    func selectSubtitleTrack(id: Int) {
        Task { await engine.selectSubtitleTrack(index: id) }
    }

    // MARK: - Scrubbing

    /// Effective duration: prefer engine, fall back to Jellyfin's runTimeTicks.
    var effectiveDuration: Double {
        if engine.duration > 0 { return engine.duration }
        if let ticks = item.runTimeTicks, ticks > 0 {
            return Double(ticks) / 10_000_000
        }
        return 0
    }

    func beginScrub() {
        guard effectiveDuration > 0 else { return }
        isScrubbing = true
        didMoveScrub = false
        scrubStartTime = engine.currentTime
        scrubProgress = Float(scrubStartTime / effectiveDuration)
        scrubTime = formatSeconds(scrubStartTime)
        showControls = true
        controlsTimer?.cancel()
    }

    func updateScrub(normalizedDelta: CGFloat) {
        let dur = effectiveDuration
        guard isScrubbing, dur > 0 else { return }
        // Map full touch surface swipe to ~30% of duration for natural feel
        let timeDelta = Double(normalizedDelta) * dur * 0.3
        let targetTime = max(0, min(dur, scrubStartTime + timeDelta))
        scrubProgress = Float(targetTime / dur)
        scrubTime = formatSeconds(targetTime)
        if abs(targetTime - scrubStartTime) > 1.0 {
            didMoveScrub = true
        }
    }

    /// Re-baseline so the next pan starts from the *current* scrub position
    /// instead of always from the engine's playback position.
    func continueScrub() {
        guard isScrubbing else {
            beginScrub()
            return
        }
        let dur = effectiveDuration
        scrubStartTime = Double(scrubProgress) * dur
    }

    func commitScrub() {
        let dur = effectiveDuration
        guard isScrubbing, dur > 0 else {
            isScrubbing = false
            return
        }
        let targetTime = Double(scrubProgress) * dur
        isScrubbing = false
        Task {
            await engine.seek(to: targetTime)
            scheduleControlsHide()
        }
    }

    func cancelScrub() {
        isScrubbing = false
        didMoveScrub = false
        scheduleControlsHide()
    }

    func showControlsTemporarily() {
        showControls = true
        scheduleControlsHide()
    }

    /// Native tvOS player click behavior:
    /// - Closed overlay → open it (no playback change)
    /// - Open overlay + playing → pause
    /// - Open overlay + paused → resume
    func handleClick() {
        if !showControls {
            showControls = true
            scheduleControlsHide()
            return
        }
        engine.togglePlayPause()
        showControls = true
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        controlsTimer?.cancel()
        guard isPlaying else { return }
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            showControls = false
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - State Observer

    private func startStateObserver() {
        stateObserver = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }

                // Update displayed time / progress from the engine, but
                // don't overwrite during scrub (the scrub state owns the
                // displayed values until commit).
                if !isScrubbing {
                    let dur = effectiveDuration
                    let cur = engine.currentTime
                    currentTime = formatSeconds(cur)
                    let remaining = dur - cur
                    remainingTime = remaining > 0 ? "-\(formatSeconds(remaining))" : "-00:00"
                    progress = dur > 0 ? Float(cur / dur) : 0
                    if dur > 0, totalTime == "00:00" {
                        totalTime = formatSeconds(dur)
                    }
                }

                switch engine.state {
                case .playing:
                    hasStartedPlaying = true
                    isLoading = false
                    isPlaying = true
                case .paused:
                    isLoading = false
                    isPlaying = false
                case .idle:
                    isPlaying = false
                case .loading:
                    if !hasStartedPlaying {
                        isLoading = true
                    }
                case .seeking:
                    break
                case .error(let msg):
                    errorMessage = msg
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Jellyfin Session Reporting

    private var currentPositionTicks: Int64 {
        Int64(engine.currentTime * 10_000_000)
    }

    private func reportStart() async {
        guard !hasReportedStart else { return }
        hasReportedStart = true
        let report = PlaybackStartReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks,
            canSeek: true,
            playMethod: PlayMethod.directPlay.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackStart(report)
    }

    private func reportProgress() async {
        let report = PlaybackProgressReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks,
            isPaused: engine.state == .paused,
            canSeek: true,
            playMethod: PlayMethod.directPlay.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackProgress(report)
    }

    private func reportStop() async {
        let report = PlaybackStopReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks
        )
        try? await playbackService.reportPlaybackStopped(report)
    }

    private func startProgressReporting() {
        progressTimer?.cancel()
        progressTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await reportProgress()
            }
        }
    }

    private func stopProgressReporting() {
        progressTimer?.cancel()
        progressTimer = nil
    }
}

private enum PlayerEngineError: LocalizedError {
    case noSource
    case noURL

    var errorDescription: String? {
        switch self {
        case .noSource: "No media source available"
        case .noURL: "Could not build stream URL"
        }
    }
}
