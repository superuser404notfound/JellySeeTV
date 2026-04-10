import Foundation
import Observation

/// ViewModel that bridges PlayerEngine with the UI and Jellyfin session reporting.
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
    /// Progress shown on the bar: scrub position during scrub, live position otherwise
    var displayedProgress: Float { isScrubbing ? scrubProgress : progress }
    private var scrubStartTime: Double = 0

    let item: JellyfinItem
    let engine = PlayerEngine()

    private let playbackService: JellyfinPlaybackServiceProtocol
    private let userID: String
    private let startFromBeginning: Bool
    private var cachedPlaybackInfo: PlaybackInfoResponse?
    private var progressTimer: Task<Void, Never>?
    private var controlsTimer: Task<Void, Never>?
    private var stateObserver: Task<Void, Never>?
    private var hasReportedStart = false
    private var mediaSourceID: String = ""
    private var playSessionID: String?
    #if !targetEnvironment(simulator)
    private var cachedDemuxer: Demuxer?
    #endif

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String, cachedPlaybackInfo: PlaybackInfoResponse? = nil, cachedDemuxer: Demuxer? = nil) {
        self.item = item
        self.startFromBeginning = startFromBeginning
        self.playbackService = playbackService
        self.userID = userID
        self.cachedPlaybackInfo = cachedPlaybackInfo
        #if !targetEnvironment(simulator)
        self.cachedDemuxer = cachedDemuxer
        #endif
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
                    itemID: item.id, userID: userID,
                    profile: DirectPlayProfile.customEngineProfile()
                )
            }
            playSessionID = info.playSessionId

            guard let source = info.mediaSources.first else {
                throw PlayerEngineError.noSource
            }
            mediaSourceID = source.id

            // Build DirectPlay URL (no Static -- FFmpeg handles HTTP streaming natively)
            guard let url = playbackService.buildStreamURL(
                itemID: item.id, mediaSourceID: source.id,
                container: source.container, isStatic: false
            ) else {
                throw PlayerEngineError.noURL
            }

            // Start position
            let startPos: Double? = if !startFromBeginning,
                let ticks = item.userData?.playbackPositionTicks, ticks > 0 {
                ticks.ticksToSeconds
            } else {
                nil
            }

            // Load and start engine (use pre-opened demuxer if available)
            #if !targetEnvironment(simulator)
            let dmx = cachedDemuxer
            cachedDemuxer = nil // consumed
            try await engine.load(url: url, startPosition: startPos, cachedDemuxer: dmx)
            #else
            try await engine.load(url: url, startPosition: startPos)
            #endif

            // Update UI
            totalTime = formatSeconds(effectiveDuration)
            isLoading = false
            isPlaying = true

            // Start observers
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
        // Pause: keep controls visible. Play: schedule auto-hide
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

    // MARK: - Scrubbing

    /// Effective duration: prefer engine, fall back to Jellyfin's runTimeTicks.
    var effectiveDuration: Double {
        if engine.duration > 0 { return engine.duration }
        if let ticks = item.runTimeTicks, ticks > 0 {
            return Double(ticks) / 10_000_000
        }
        return 0
    }

    /// Called when user starts panning on remote touch surface.
    func beginScrub() {
        guard effectiveDuration > 0 else { return }
        isScrubbing = true
        scrubStartTime = engine.currentTime
        scrubProgress = progress
        showControls = true
        controlsTimer?.cancel()
    }

    /// Called during pan — normalizedDelta is -1.0 to 1.0 relative to touch surface.
    func updateScrub(normalizedDelta: CGFloat) {
        let dur = effectiveDuration
        guard isScrubbing, dur > 0 else { return }
        // Map full touch surface swipe to ~30% of duration for natural feel
        let timeDelta = Double(normalizedDelta) * dur * 0.3
        let targetTime = max(0, min(dur, scrubStartTime + timeDelta))
        scrubProgress = Float(targetTime / dur)
        scrubTime = formatSeconds(targetTime)
    }

    /// Called when pan ends — commit the seek.
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

    /// Cancel scrub — return to original position.
    func cancelScrub() {
        isScrubbing = false
        scheduleControlsHide()
    }

    func showControlsTemporarily() {
        showControls = true
        scheduleControlsHide()
    }

    func toggleControls() {
        if showControls {
            showControls = false
            controlsTimer?.cancel()
        } else {
            showControlsTemporarily()
        }
    }

    private func scheduleControlsHide() {
        controlsTimer?.cancel()
        // Don't auto-hide when paused
        guard isPlaying else { return }
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            showControls = false
        }
    }

    // MARK: - State Observer

    private func startStateObserver() {
        stateObserver = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }

                // Update from engine (use effective duration as fallback)
                let dur = effectiveDuration
                let cur = engine.currentTime
                currentTime = formatSeconds(cur)
                let remaining = dur - cur
                remainingTime = remaining > 0 ? "-\(formatSeconds(remaining))" : "-00:00"
                progress = dur > 0 ? Float(cur / dur) : 0

                #if !targetEnvironment(simulator)
                switch engine.state {
                case .playing: isPlaying = true; isLoading = false
                case .paused: isPlaying = false
                case .idle: isPlaying = false
                case .loading: isLoading = true
                case .seeking: break // Keep current state
                case .error(let msg): errorMessage = msg; isLoading = false
                }
                #endif
            }
        }
    }

    // MARK: - Time Formatting

    private func formatSeconds(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Jellyfin Session Reporting

    private var currentPositionTicks: Int64 {
        Int64(engine.currentTime * 10_000_000)
    }

    private func reportStart() async {
        guard !hasReportedStart else { return }
        hasReportedStart = true
        let report = PlaybackStartReport(
            itemId: item.id, mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks,
            canSeek: true, playMethod: PlayMethod.directPlay.rawValue,
            audioStreamIndex: nil, subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackStart(report)
    }

    private func reportProgress() async {
        let report = PlaybackProgressReport(
            itemId: item.id, mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks,
            isPaused: !isPlaying, canSeek: true,
            playMethod: PlayMethod.directPlay.rawValue,
            audioStreamIndex: nil, subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackProgress(report)
    }

    private func reportStop() async {
        let report = PlaybackStopReport(
            itemId: item.id, mediaSourceId: mediaSourceID,
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
        controlsTimer?.cancel()
        controlsTimer = nil
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
