import Foundation
import Observation
import SteelPlayer

/// ViewModel that bridges SteelPlayer with Jellyfin session reporting
/// and our custom tvOS-style player UI.
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
    var didMoveScrub = false
    var displayedProgress: Float { isScrubbing ? scrubProgress : progress }
    private var scrubStartTime: Double = 0

    let item: JellyfinItem
    let player = SteelPlayer()

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

            // Build URL — prefer transcodingUrl (HLS remux), else direct stream
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

            // Load with SteelPlayer — this opens the demuxer, starts
            // the decoder, and begins the render loop.
            try await player.load(url: url, startPosition: startPos)

            totalTime = formatSeconds(effectiveDuration)
            isLoading = false
            isPlaying = true

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
        player.stop()
    }

    // MARK: - Controls

    func togglePlayPause() {
        player.togglePlayPause()
        showControls = true
        scheduleControlsHide()
    }

    func seekForward() {
        Task { await player.seek(to: player.currentTime + 10) }
        showControlsTemporarily()
    }

    func seekBackward() {
        Task { await player.seek(to: player.currentTime - 10) }
        showControlsTemporarily()
    }

    func selectAudioTrack(id: Int) {
        player.selectAudioTrack(index: id)
    }

    func selectSubtitleTrack(id: Int) {
        player.selectSubtitleTrack(index: id)
    }

    // MARK: - Scrubbing

    var effectiveDuration: Double {
        if player.duration > 0 { return player.duration }
        if let ticks = item.runTimeTicks, ticks > 0 {
            return Double(ticks) / 10_000_000
        }
        return 0
    }

    func beginScrub() {
        guard effectiveDuration > 0 else { return }
        isScrubbing = true
        didMoveScrub = false
        scrubStartTime = player.currentTime
        scrubProgress = Float(scrubStartTime / effectiveDuration)
        scrubTime = formatSeconds(scrubStartTime)
        showControls = true
        controlsTimer?.cancel()
    }

    func updateScrub(normalizedDelta: CGFloat) {
        let dur = effectiveDuration
        guard isScrubbing, dur > 0 else { return }
        let timeDelta = Double(normalizedDelta) * dur * 0.3
        let targetTime = max(0, min(dur, scrubStartTime + timeDelta))
        scrubProgress = Float(targetTime / dur)
        scrubTime = formatSeconds(targetTime)
        if abs(targetTime - scrubStartTime) > 1.0 {
            didMoveScrub = true
        }
    }

    func continueScrub() {
        guard isScrubbing else {
            beginScrub()
            return
        }
        scrubStartTime = Double(scrubProgress) * effectiveDuration
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
            await player.seek(to: targetTime)
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

    func handleClick() {
        if !showControls {
            showControls = true
            scheduleControlsHide()
            return
        }
        player.togglePlayPause()
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

                if !isScrubbing {
                    let dur = effectiveDuration
                    let cur = player.currentTime
                    currentTime = formatSeconds(cur)
                    let remaining = dur - cur
                    remainingTime = remaining > 0 ? "-\(formatSeconds(remaining))" : "-00:00"
                    progress = dur > 0 ? Float(cur / dur) : 0
                    let formattedDur = dur > 0 ? formatSeconds(dur) : "00:00"
                    if totalTime != formattedDur {
                        totalTime = formattedDur
                    }
                }

                switch player.state {
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
        Int64(player.currentTime * 10_000_000)
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
            isPaused: player.state == .paused,
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
