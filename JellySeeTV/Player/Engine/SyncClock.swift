import Foundation

/// Decision for video frame display timing
enum FrameAction {
    /// Display this frame now
    case display
    /// Frame is too late, skip it
    case drop
    /// Frame is too early, wait this many seconds
    case wait(TimeInterval)
}

/// Audio-master A/V sync clock.
/// Video frames are timed relative to the audio output position.
final class SyncClock {
    private let audioOutput: AudioOutput

    /// Maximum allowed drift before dropping frames (seconds)
    private let dropThreshold: TimeInterval = 0.04 // 40ms

    /// Maximum allowed lead time before waiting (seconds)
    private let waitThreshold: TimeInterval = 0.02 // 20ms

    init(audioOutput: AudioOutput) {
        self.audioOutput = audioOutput
    }

    /// Current master clock time in seconds (from audio output)
    var currentTime: Double {
        audioOutput.currentPlaybackTime
    }

    /// Determine what to do with a video frame
    func shouldDisplay(framePTS: Double) -> FrameAction {
        let clock = currentTime
        let diff = framePTS - clock // positive = frame is ahead, negative = frame is behind

        if diff < -dropThreshold {
            // Frame is too late -- drop it
            return .drop
        } else if diff > waitThreshold {
            // Frame is too early -- wait
            return .wait(diff - waitThreshold / 2)
        } else {
            // Frame is within sync window -- display
            return .display
        }
    }

    var isPaused: Bool {
        audioOutput.isPaused
    }
}
