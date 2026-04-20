import Foundation
import AetherEngine

extension PlayerViewModel {

    var effectiveDuration: Double {
        if player.duration > 0 { return player.duration }
        if let ticks = item.runTimeTicks, ticks > 0 {
            return Double(ticks) / 10_000_000
        }
        return 0
    }

    func scrub(delta: CGFloat) {
        let dur = effectiveDuration
        guard dur > 0 else { return }

        if !isScrubbing {
            isScrubbing = true
            scrubStartProgress = progress
            showControls = true
            controlsTimer?.cancel()
        }

        scrubProgress = max(0, min(1, scrubStartProgress + Float(delta) * 0.3))
        scrubTime = formatSeconds(Double(scrubProgress) * dur)
    }

    func scrubPanEnded() {
        if isScrubbing {
            scrubStartProgress = scrubProgress
        }
    }

    func commitScrub() {
        let dur = effectiveDuration
        guard isScrubbing, dur > 0 else {
            isScrubbing = false
            return
        }
        let targetTime = Double(scrubProgress) * dur
        // Set progress to scrub position BEFORE clearing isScrubbing.
        // Without this, displayedProgress snaps from scrubProgress back
        // to the old progress value for a brief moment before the seek
        // completes and Combine updates it.
        progress = scrubProgress
        isScrubbing = false
        // Record the user's seek target synchronously so reportStop()
        // (or a reportProgress mid-seek) sees the intended position
        // even if the user dismisses before player.seek completes.
        // The Combine pipeline player.$currentTime → playbackTime
        // has one run-loop tick of latency; without this, "resume"
        // would jump back to the pre-seek position.
        playbackTime = targetTime
        Task {
            await player.seek(to: targetTime)
            reportProgressIfNeeded()
            scheduleControlsHide()
        }
    }

    func cancelScrub() {
        isScrubbing = false
        scheduleControlsHide()
    }
}
