import Foundation
import AetherEngine

extension PlayerViewModel {

    func checkForNextEpisode() {
        let dur = effectiveDuration
        let remaining = dur - playbackTime
        guard dur > 0, remaining < 30, remaining > 0,
              !hasFetchedNextEpisode else { return }

        guard item.seriesId != nil else { return }

        hasFetchedNextEpisode = true
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
                return
            }

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
                }
            }
        } catch {
            #if DEBUG
            print("[NextEpisode] Fetch failed: \(error)")
            #endif
        }
    }

    func startNextEpisodeCountdown() {
        // If autoplay is disabled, still show the overlay (so the user
        // can pick next manually) but skip the timer that auto-transitions.
        guard preferences.autoplayNextEpisode else {
            isCountdownActive = false
            nextEpisodeCountdown = 0
            return
        }

        // If the user set countdown to 0, skip straight to the next episode.
        let configured = preferences.nextEpisodeCountdownSeconds
        guard configured > 0 else {
            Task { @MainActor [weak self] in await self?.playNextEpisode() }
            return
        }

        nextEpisodeCountdown = configured
        isCountdownActive = true
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
        nextEpisodeTimer = nil
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
        errorMessage = nil
        videoFormat = .sdr
        subtitleCues = []
        subtitleStreams = []
        activeSubtitleIndex = nil
        activeAudioIndex = nil
        nextEpisode = nil
        hasFetchedNextEpisode = false
        nextEpisodeCancelled = false
        nextEpisodeCountdown = 10
        isCountdownActive = false
        hasReportedStart = false
        hasStartedPlaying = false
        showControls = false
        isScrubbing = false
        controlsFocus = .progressBar
        trackDropdown = .none
        progress = 0
        playbackTime = 0
        resumePositionTicks = 0
        introSegment = nil
        isInsideIntro = false
        didAutoSkipCurrentIntro = false

        // Start new
        await startPlayback()
    }

    func cancelNextEpisode() {
        nextEpisodeTimer?.cancel()
        nextEpisodeTimer = nil
        showNextEpisodeOverlay = false
        isCountdownActive = false
        nextEpisodeCancelled = true
    }
}
