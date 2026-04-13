import SwiftUI

/// Displays the current subtitle text at the bottom of the player,
/// synchronized to the playback position.
struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let currentTime: Double

    var body: some View {
        VStack {
            Spacer()

            if let activeCue = findActiveCue() {
                Text(activeCue.text)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 120)
                    .padding(.bottom, 80)
                    .transition(.opacity)
                    .id(activeCue.id)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: findActiveCue()?.id)
        .allowsHitTesting(false)
    }

    private func findActiveCue() -> SubtitleCue? {
        // Binary search for efficiency on large subtitle files
        var low = 0
        var high = cues.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]

            if currentTime < cue.startTime {
                high = mid - 1
            } else if currentTime > cue.endTime {
                low = mid + 1
            } else {
                return cue
            }
        }

        return nil
    }
}
