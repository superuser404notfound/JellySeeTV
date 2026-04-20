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
        } catch {
            #if DEBUG
            print("[SessionReport] Progress FAILED: \(error)")
            #endif
        }
    }

    func reportStop(positionTicks: Int64? = nil) async {
        // Optional override lets stopPlayback() capture the position
        // BEFORE killing the engine, so we can stop audio first (no
        // trailing buffer on dismiss) without losing the right position.
        let ticks = positionTicks ?? currentPositionTicks
        let report = PlaybackStopReport(
            itemId: item.id,
            mediaSourceId: mediaSourceID,
            playSessionId: playSessionID,
            positionTicks: ticks
        )
        do {
            try await playbackService.reportPlaybackStopped(report)
            // Tell HomeView (and anyone else listening) that the
            // server now has updated progress for this item, so
            // Continue Watching / Next Up should be refreshed the
            // next time those views appear.
            NotificationCenter.default.post(name: .playbackProgressDidChange, object: nil)
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
}
