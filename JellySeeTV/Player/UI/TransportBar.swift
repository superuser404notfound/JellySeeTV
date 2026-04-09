import SwiftUI

/// Native tvOS-style transport bar for the video player.
/// Matches the system player's layout: progress bar, elapsed/remaining time.
struct TransportBar: View {
    let progress: Float
    let currentTime: String
    let remainingTime: String
    let isPlaying: Bool
    let onSeekBackward: () -> Void
    let onTogglePlayPause: () -> Void
    let onSeekForward: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Progress bar
            progressBar

            // Time labels + controls
            HStack(alignment: .center) {
                Text(currentTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                // Skip buttons
                HStack(spacing: 40) {
                    Button(action: onSeekBackward) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 28, weight: .medium))
                    }
                    .buttonStyle(.plain)

                    Button(action: onTogglePlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .medium))
                    }
                    .buttonStyle(.plain)

                    Button(action: onSeekForward) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 28, weight: .medium))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(remainingTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 60)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knobX = max(0, min(width, width * CGFloat(progress)))

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: 4)

                // Filled track
                Capsule()
                    .fill(.white)
                    .frame(width: knobX, height: 4)

                // Playhead knob
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: knobX - 6)
            }
        }
        .frame(height: 12)
    }
}

/// Title overlay that appears at the top of the player when transport is visible.
struct PlayerTitleOverlay: View {
    let item: JellyfinItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Series name or movie title
            if let seriesName = item.seriesName {
                Text(seriesName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // Episode info
                let episodeLabel = episodeDescription
                if !episodeLabel.isEmpty {
                    Text(episodeLabel)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            } else {
                Text(item.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let year = item.productionYear {
                    Text(String(year))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 60)
    }

    private var episodeDescription: String {
        var parts: [String] = []
        if let season = item.parentIndexNumber {
            parts.append("S\(season)")
        }
        if let episode = item.indexNumber {
            parts.append("E\(episode)")
        }
        let prefix = parts.joined(separator: "")
        if prefix.isEmpty {
            return item.name
        }
        return "\(prefix) \(item.name)"
    }
}
