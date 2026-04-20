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

        // Capture identifiers up front so anything we hand to the
        // server is a snapshot of the episode we're playing right
        // now, even if `item` mutates underneath us mid-await.
        let currentID = item.id
        let currentIndex = item.indexNumber
        let currentSeasonID = item.seasonId

        // Force a progress report so Jellyfin knows we're near the
        // end. Without this, NextUp returns the current episode
        // because Jellyfin hasn't marked it as "watched" yet.
        await reportProgress()

        do {
            // Jellyfin's NextUp endpoint. Discard if it gives us the
            // current episode back (still possible even after the
            // progress report on some server configs).
            if let next = try await playbackService.getNextEpisode(
                seriesID: seriesID, userID: userID
            ), next.id != currentID {
                nextEpisode = next
                return
            }

            // Fallback: walk the season's episode list and pick the
            // one whose indexNumber is the lowest value greater than
            // the current one. This handles servers that:
            //   - return episodes out of indexNumber order
            //   - return the current episode in NextUp
            //   - have gaps in indexNumber (mid-season specials etc.)
            guard let currentSeasonID, let currentIndex else { return }
            let episodes = try await playbackService.getEpisodes(
                seriesID: seriesID, seasonID: currentSeasonID, userID: userID
            )
            let candidate = episodes
                .filter { $0.id != currentID }
                .filter { ($0.indexNumber ?? -1) > currentIndex }
                .min { ($0.indexNumber ?? .max) < ($1.indexNumber ?? .max) }
            if let candidate {
                nextEpisode = candidate
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
