import Foundation
import AetherEngine

extension PlayerViewModel {

    /// Stable position in Jellyfin ticks, derived from playbackTime (updated
    /// by Combine every 250ms). Survives player.stop() — unlike player.currentTime
    /// which resets to 0 immediately. Uses max(playback, resume) to prevent
    /// reporting 0 before the first time update arrives.
    var currentPositionTicks: Int64 {
        let ticks = Int64(playbackTime * 10_000_000)
        return max(ticks, resumePositionTicks)
    }

    func reportStart() async {
        guard !hasReportedStart else { return }
        hasReportedStart = true
        let ticks = currentPositionTicks
        let report = PlaybackStartReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: ticks,
            canSeek: true,
            playMethod: activePlayMethod.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        do {
            try await playbackService.reportPlaybackStart(report)
            #if DEBUG
            print("[SessionReport] Start: \(formatTicks(ticks))")
            #endif
        } catch {
            #if DEBUG
            print("[SessionReport] Start FAILED: \(error)")
            #endif
        }
    }

    func reportProgress() async {
        let ticks = currentPositionTicks
        guard ticks > 0 else { return } // Don't report position 0
        let report = PlaybackProgressReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: ticks,
            isPaused: !isPlaying,
            canSeek: true,
            playMethod: activePlayMethod.rawValue,
            audioStreamIndex: nil,
            subtitleStreamIndex: nil
        )
        do {
            try await playbackService.reportPlaybackProgress(report)
            #if DEBUG
            print("[SessionReport] Progress: \(formatTicks(ticks))\(isPlaying ? "" : " (paused)")")
            #endif
        } catch {
            #if DEBUG
            print("[SessionReport] Progress FAILED: \(error)")
            #endif
        }
    }

    func reportStop() async {
        let ticks = currentPositionTicks
        let report = PlaybackStopReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: ticks
        )
        do {
            try await playbackService.reportPlaybackStopped(report)
            #if DEBUG
            print("[SessionReport] Stop: \(formatTicks(ticks))")
            #endif
        } catch {
            #if DEBUG
            print("[SessionReport] Stop FAILED: \(error)")
            #endif
        }
    }

    func startProgressReporting() {
        progressTimer?.cancel()
        progressTimer = Task {
            // Wait briefly for the first time update to arrive,
            // then report immediately so short views are tracked.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await reportProgress()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                await reportProgress()
            }
        }
    }

    /// Report progress on pause/seek so Jellyfin always has the latest position.
    func reportProgressIfNeeded() {
        Task { await reportProgress() }
    }

    func stopProgressReporting() {
        progressTimer?.cancel()
        progressTimer = nil
    }

    #if DEBUG
    private func formatTicks(_ ticks: Int64) -> String {
        let seconds = Int(ticks / 10_000_000)
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d (%lld ticks)", m, s, ticks)
    }
    #endif
}
