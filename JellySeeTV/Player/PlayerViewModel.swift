import Foundation
import Observation

/// ViewModel that bridges the AVPlayer engine with Jellyfin session
/// reporting. Most of the player UI state (scrubbing, transport bar,
/// audio/subtitle picker, controls visibility) lives inside
/// AVPlayerViewController itself — we only own the lifecycle and
/// the start/progress/stop reporting back to Jellyfin.
@Observable
@MainActor
final class PlayerViewModel {
    var isLoading = true
    var errorMessage: String?

    let item: JellyfinItem
    let engine = AVPlayerEngine()

    private let playbackService: JellyfinPlaybackServiceProtocol
    private let userID: String
    private let startFromBeginning: Bool
    private var cachedPlaybackInfo: PlaybackInfoResponse?
    private var progressTimer: Task<Void, Never>?
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
                    profile: DirectPlayProfile.avPlayerProfile()
                )
            }
            playSessionID = info.playSessionId

            guard let source = info.mediaSources.first else {
                throw PlayerEngineError.noSource
            }
            mediaSourceID = source.id

            // Build streaming URL. AVPlayer prefers HLS / fragmented MP4 —
            // Jellyfin will pick the right path based on the device profile.
            guard let url = playbackService.buildStreamURL(
                itemID: item.id,
                mediaSourceID: source.id,
                container: source.container,
                isStatic: false
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

            try await engine.load(url: url, startPosition: startPos)

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

    // MARK: - State Observer

    private func startStateObserver() {
        stateObserver = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }

                switch engine.state {
                case .playing:
                    hasStartedPlaying = true
                    isLoading = false
                case .paused:
                    isLoading = false
                case .idle:
                    break
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
