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
    /// True if the user actually moved the scrub position (not just touched briefly)
    var didMoveScrub = false
    /// Progress shown on the bar: scrub position during scrub, live position otherwise
    var displayedProgress: Float { isScrubbing ? scrubProgress : progress }
    private var scrubStartTime: Double = 0

    let item: JellyfinItem
    let engine = VLCPlayerEngine()

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

            // Load and start engine
            try await engine.load(url: url, startPosition: startPos)

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

    /// Called when user starts panning on remote touch surface.
    /// Captures the CURRENT engine position as the scrub baseline.
    func beginScrub() {
        guard effectiveDuration > 0 else { return }
        isScrubbing = true
        didMoveScrub = false
        // Use the current engine time (already includes displayTimeOffset after seek)
        scrubStartTime = engine.currentTime
        scrubProgress = Float(scrubStartTime / effectiveDuration)
        scrubTime = formatSeconds(scrubStartTime)
        showControls = true
        controlsTimer?.cancel()
        #if DEBUG
        print("[Scrub] Begin at \(String(format: "%.1f", scrubStartTime))s")
        #endif
    }

    /// Called during pan — normalizedDelta is -1.0 to 1.0 relative to touch surface.
    /// Each pan gesture is RELATIVE: the delta from the start of THIS pan, not cumulative.
    func updateScrub(normalizedDelta: CGFloat) {
        let dur = effectiveDuration
        guard isScrubbing, dur > 0 else { return }
        // Map full touch surface swipe to ~30% of duration for natural feel
        let timeDelta = Double(normalizedDelta) * dur * 0.3
        let targetTime = max(0, min(dur, scrubStartTime + timeDelta))
        scrubProgress = Float(targetTime / dur)
        scrubTime = formatSeconds(targetTime)
        // Mark as moved if delta is meaningful (>1 second from origin)
        if abs(targetTime - scrubStartTime) > 1.0 {
            didMoveScrub = true
        }
    }

    /// Called when a new pan gesture starts (after a previous one ended).
    /// Re-baselines the scrub from the CURRENT scrub position, so successive
    /// pans accumulate naturally instead of always starting from the engine position.
    func continueScrub() {
        guard isScrubbing else {
            beginScrub()
            return
        }
        // Re-baseline at the current scrub target so the next pan is relative to it
        let dur = effectiveDuration
        scrubStartTime = Double(scrubProgress) * dur
        #if DEBUG
        print("[Scrub] Continue from \(String(format: "%.1f", scrubStartTime))s")
        #endif
    }

    /// Called when user clicks to confirm the scrub. Performs the actual seek.
    func commitScrub() {
        let dur = effectiveDuration
        guard isScrubbing, dur > 0 else {
            isScrubbing = false
            return
        }
        let targetTime = Double(scrubProgress) * dur
        isScrubbing = false
        #if DEBUG
        print("[Scrub] Commit to \(String(format: "%.1f", targetTime))s")
        #endif
        Task {
            await engine.seek(to: targetTime)
            scheduleControlsHide()
        }
    }

    /// Cancel scrub — return to original position.
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
    /// - Closed overlay → open overlay (don't change playback)
    /// - Open overlay + playing → pause (keep overlay)
    /// - Open overlay + paused → resume (keep overlay)
    func handleClick() {
        if !showControls {
            showControls = true
            scheduleControlsHide()
            return
        }
        // Overlay is open → toggle playback
        engine.togglePlayPause()
        // Keep overlay visible after the toggle
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
                // Don't overwrite display values during scrub or seek
                if !isScrubbing {
                    let dur = effectiveDuration
                    let cur = engine.currentTime
                    currentTime = formatSeconds(cur)
                    let remaining = dur - cur
                    remainingTime = remaining > 0 ? "-\(formatSeconds(remaining))" : "-00:00"
                    progress = dur > 0 ? Float(cur / dur) : 0
                }

                switch engine.state {
                case .playing: isPlaying = true; isLoading = false
                case .paused: isPlaying = false
                case .idle: isPlaying = false
                case .loading: isLoading = true
                case .seeking: break // Keep current state
                case .error(let msg): errorMessage = msg; isLoading = false
                }
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
