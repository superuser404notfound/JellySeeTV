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
    var progress: Float = 0

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

            // Build DirectPlay URL (always Static=true, our engine handles everything)
            guard let url = playbackService.buildStreamURL(
                itemID: item.id, mediaSourceID: source.id,
                container: source.container, isStatic: true
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
            totalTime = formatSeconds(engine.duration)
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
        showControlsTemporarily()
    }

    func seekForward() {
        Task { await engine.seek(to: engine.currentTime + 10) }
        showControlsTemporarily()
    }

    func seekBackward() {
        Task { await engine.seek(to: engine.currentTime - 10) }
        showControlsTemporarily()
    }

    func showControlsTemporarily() {
        showControls = true
        controlsTimer?.cancel()
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

                // Update from engine
                currentTime = formatSeconds(engine.currentTime)
                progress = engine.progress

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
