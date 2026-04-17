import Foundation
import AetherEngine

extension PlayerViewModel {

    func checkForNextEpisode() {
        let dur = effectiveDuration
        let remaining = dur - playbackTime
        guard dur > 0, remaining < 30, remaining > 0,
              !hasFetchedNextEpisode else { return }

        guard item.seriesId != nil else {
            #if DEBUG
            if !hasFetchedNextEpisode && remaining < 30 && remaining > 0 {
                print("[NextEpisode] Skipped: seriesId=nil, type=\(item.type)")
            }
            #endif
            return
        }

        hasFetchedNextEpisode = true
        #if DEBUG
        print("[NextEpisode] Triggering fetch: remaining=\(String(format: "%.0f", remaining))s, type=\(item.type), seriesId=\(item.seriesId ?? "nil")")
        #endif
        Task { await fetchNextEpisode() }
    }

    private func fetchNextEpisode() async {
        guard let seriesID = item.seriesId else { return }

        // Force a progress report so Jellyfin knows we're near the end.
        // Without this, NextUp returns the current episode because
        // Jellyfin hasn't marked it as "watched" yet.
        await reportProgress()

        do {
            let next = try await playbackService.getNextEpisode(seriesID: seriesID, userID: userID)
            if let next, next.id != item.id {
                nextEpisode = next
                #if DEBUG
                print("[NextEpisode] Found: \(next.name) (S\(next.parentIndexNumber ?? 0)E\(next.indexNumber ?? 0))")
                #endif
                return
            }

            #if DEBUG
            if next != nil { print("[NextEpisode] NextUp returned current episode, trying by index") }
            else { print("[NextEpisode] NextUp returned nil, trying by index") }
            #endif

            // NextUp failed (returned current or nil). Try to find
            // the next episode by index number in the same season.
            if let seasonID = item.seasonId,
               let currentIndex = item.indexNumber {
                let episodes = try await playbackService.getEpisodes(
                    seriesID: seriesID, seasonID: seasonID, userID: userID
                )
                if let nextEp = episodes.first(where: {
                    ($0.indexNumber ?? 0) == currentIndex + 1
                }) {
                    nextEpisode = nextEp
                    #if DEBUG
                    print("[NextEpisode] Found by index: \(nextEp.name) (S\(nextEp.parentIndexNumber ?? 0)E\(nextEp.indexNumber ?? 0))")
                    #endif
                } else {
                    #if DEBUG
                    print("[NextEpisode] No next episode in season")
                    #endif
                }
            }
        } catch {
            #if DEBUG
            print("[NextEpisode] Fetch failed: \(error)")
            #endif
        }
    }

    func startNextEpisodeCountdown() {
        #if DEBUG
        print("[NextEpisode] Countdown starts (10s)")
        #endif
        nextEpisodeTimer?.cancel()
        nextEpisodeTimer = Task {
            while nextEpisodeCountdown > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                nextEpisodeCountdown -= 1
            }
            guard !Task.isCancelled else { return }
            // Launch in a NEW task — if we called playNextEpisode() directly,
            // cancelling nextEpisodeTimer would cancel the playback startup
            // (CancellationError in player.load → "abgebrochen").
            Task { @MainActor [weak self] in
                await self?.playNextEpisode()
            }
        }
    }

    func playNextEpisode() async {
        guard let next = nextEpisode else { return }
        nextEpisodeTimer?.cancel()
        showNextEpisodeOverlay = false

        // Stop current
        stopProgressReporting()
        cancellables.removeAll()
        await reportStop()
        player.stop()

        // Reset state
        item = next
        startFromBeginning = true
        cachedPlaybackInfo = nil
        subtitleCues = []
        activeSubtitleIndex = nil
        activeAudioIndex = nil
        nextEpisode = nil
        hasFetchedNextEpisode = false
        nextEpisodeCancelled = false
        nextEpisodeCountdown = 10
        hasReportedStart = false
        hasStartedPlaying = false
        showControls = false
        isScrubbing = false
        controlsFocus = .progressBar
        trackDropdown = .none
        progress = 0
        playbackTime = 0
        resumePositionTicks = 0

        // Start new
        await startPlayback()
    }

    func cancelNextEpisode() {
        nextEpisodeTimer?.cancel()
        showNextEpisodeOverlay = false
        nextEpisodeCancelled = true
    }
}
