import AVFoundation
import Observation

@Observable
@MainActor
final class PlayerViewModel {
    var isLoading = true
    var errorMessage: String?

    let item: JellyfinItem
    let startFromBeginning: Bool
    let coordinator: PlaybackCoordinator

    private let playbackService: JellyfinPlaybackServiceProtocol
    private var progressTimer: Task<Void, Never>?
    private var hasReportedStart = false

    init(
        item: JellyfinItem,
        startFromBeginning: Bool,
        playbackService: JellyfinPlaybackServiceProtocol,
        userID: String
    ) {
        self.item = item
        self.startFromBeginning = startFromBeginning
        self.playbackService = playbackService
        self.coordinator = PlaybackCoordinator(playbackService: playbackService, userID: userID)
    }

    func startPlayback() async {
        isLoading = true
        errorMessage = nil

        do {
            try await coordinator.preparePlayback(item: item, startFromBeginning: startFromBeginning)
            isLoading = false
            startPlayerStatusObserver()
            await reportStart()
            startProgressReporting()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func startPlayerStatusObserver() {
        // Watch for player to actually start rendering frames
        Task {
            while !Task.isCancelled {
                if coordinator.player.timeControlStatus == .playing ||
                   coordinator.player.currentItem?.status == .readyToPlay {
                    isLoading = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func stopPlayback() async {
        stopProgressReporting()
        await reportStop()
        coordinator.stop()
    }

    // MARK: - Session Reporting

    private func reportStart() async {
        guard !hasReportedStart else { return }
        hasReportedStart = true

        let report = PlaybackStartReport(
            itemId: item.id,
            mediaSourceId: coordinator.mediaSourceID,
            playSessionId: coordinator.playSessionID,
            positionTicks: coordinator.currentPositionTicks,
            canSeek: true,
            playMethod: coordinator.playMethod.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackStart(report)
    }

    private func reportProgress() async {
        let report = PlaybackProgressReport(
            itemId: item.id,
            mediaSourceId: coordinator.mediaSourceID,
            playSessionId: coordinator.playSessionID,
            positionTicks: coordinator.currentPositionTicks,
            isPaused: coordinator.isPaused,
            canSeek: true,
            playMethod: coordinator.playMethod.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackProgress(report)
    }

    private func reportStop() async {
        let report = PlaybackStopReport(
            itemId: item.id,
            mediaSourceId: coordinator.mediaSourceID,
            playSessionId: coordinator.playSessionID,
            positionTicks: coordinator.currentPositionTicks
        )
        try? await playbackService.reportPlaybackStopped(report)
    }

    // MARK: - Progress Timer

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
