import SwiftUI

/// Native tvOS-style transport bar for the video player.
struct TransportBar: View {
    let progress: Float
    let currentTime: String
    let remainingTime: String
    let isPlaying: Bool
    let onSeekBackward: () -> Void
    let onTogglePlayPause: () -> Void
    let onSeekForward: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Progress bar
            progressBar

            // Time labels
            HStack {
                Text(currentTime)
                    .font(.callout)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text(remainingTime)
                    .font(.callout)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Transport buttons
            HStack(spacing: 50) {
                PlayerControlButton(
                    systemName: "gobackward.10",
                    size: 36,
                    action: onSeekBackward
                )

                PlayerControlButton(
                    systemName: isPlaying ? "pause.fill" : "play.fill",
                    size: 44,
                    action: onTogglePlayPause
                )

                PlayerControlButton(
                    systemName: "goforward.10",
                    size: 36,
                    action: onSeekForward
                )
            }
            .padding(.top, 4)
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
                    .frame(height: 6)

                // Filled track
                Capsule()
                    .fill(.white)
                    .frame(width: knobX, height: 6)

                // Playhead knob
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .offset(x: knobX - 7)
            }
        }
        .frame(height: 14)
    }
}

// MARK: - Focusable Player Button

/// A tvOS-focusable button for player controls with scale + glow on focus.
struct PlayerControlButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size + 30, height: size + 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerButtonStyle())
    }
}

/// Custom tvOS button style: scales up and glows when focused.
struct PlayerButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.2 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .shadow(color: isFocused ? .white.opacity(0.5) : .clear, radius: 10)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Title Overlay

/// Title overlay that appears at the top of the player when transport is visible.
struct PlayerTitleOverlay: View {
    let item: JellyfinItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let seriesName = item.seriesName {
                Text(seriesName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

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
