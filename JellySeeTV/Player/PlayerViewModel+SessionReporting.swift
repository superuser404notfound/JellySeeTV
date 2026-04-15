import Foundation
import SteelPlayer

extension PlayerViewModel {

    /// Current position in Jellyfin ticks. Uses the higher of player time
    /// and resume position to prevent reporting 0 when the player hasn't
    /// produced time updates yet (causes Jellyfin to reset progress).
    var currentPositionTicks: Int64 {
        let playerTicks = Int64(player.currentTime * 10_000_000)
        return max(playerTicks, resumePositionTicks)
    }

    func reportStart() async {
        guard !hasReportedStart else { return }
        hasReportedStart = true
        let report = PlaybackStartReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks,
            canSeek: true,
            playMethod: activePlayMethod.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackStart(report)
    }

    func reportProgress() async {
        let report = PlaybackProgressReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks,
            isPaused: player.state == .paused,
            canSeek: true,
            playMethod: activePlayMethod.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        try? await playbackService.reportPlaybackProgress(report)
    }

    func reportStop() async {
        let report = PlaybackStopReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: currentPositionTicks
        )
        try? await playbackService.reportPlaybackStopped(report)
    }

    func startProgressReporting() {
        progressTimer?.cancel()
        progressTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await reportProgress()
            }
        }
    }

    func stopProgressReporting() {
        progressTimer?.cancel()
        progressTimer = nil
    }
}
