import SwiftUI
import SteelPlayer

/// Native tvOS-style transport bar with progress bar, time labels,
/// and track selection buttons above the bar on the right.
///
/// Uses a custom focus system managed by PlayerViewModel (not SwiftUI
/// @FocusState) to avoid UIKit/SwiftUI focus conflicts.
///
/// Layout:
/// ```
///                              [Audio] [Subs]
/// ═══════════════════●══════════════════════
/// 00:12:34                        -01:23:45
/// ```
struct TransportBar: View {
    let progress: Float
    let currentTime: String
    let remainingTime: String
    let isScrubbing: Bool
    let scrubTime: String
    let audioTracks: [TrackInfo]
    let subtitleTracks: [TrackInfo]
    let activeSubtitleIndex: Int?
    let controlsFocus: PlayerViewModel.ControlsFocus

    var body: some View {
        VStack(spacing: 10) {
            // Scrub time preview (large, centered, only during scrub)
            if isScrubbing {
                Text(scrubTime)
                    .font(.system(size: 56, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .transition(.opacity)
                    .padding(.bottom, 16)
            }

            // Track buttons — right-aligned, above progress bar
            if !audioTracks.isEmpty || !subtitleTracks.isEmpty {
                HStack {
                    Spacer()
                    trackButtons
                }
                .padding(.bottom, 4)
            }

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
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 60)
        .animation(.easeInOut(duration: 0.2), value: isScrubbing)
        .animation(.easeInOut(duration: 0.2), value: controlsFocus)
    }

    // MARK: - Track Buttons

    private var trackButtons: some View {
        HStack(spacing: 16) {
            if !audioTracks.isEmpty {
                trackLabel(
                    title: String(localized: "player.audio", defaultValue: "Audio"),
                    icon: "speaker.wave.2",
                    isFocused: controlsFocus == .audioButton
                )
            }

            trackLabel(
                title: String(localized: "player.subtitles", defaultValue: "Subtitles"),
                icon: "captions.bubble",
                isFocused: controlsFocus == .subtitleButton
            )
        }
    }

    private func trackLabel(title: String, icon: String, isFocused: Bool) -> some View {
        Label(title, systemImage: icon)
            .font(.callout)
            .foregroundStyle(isFocused ? .white : .white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFocused ? .white.opacity(0.2) : .clear)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knobX = max(0, min(width, width * CGFloat(progress)))
            let active = isScrubbing || controlsFocus == .progressBar
            let trackHeight: CGFloat = active ? 10 : 6
            let knobSize: CGFloat = active ? 22 : 14

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: trackHeight)

                // Filled track
                Capsule()
                    .fill(.white)
                    .frame(width: knobX, height: trackHeight)

                // Playhead knob
                Circle()
                    .fill(.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .offset(x: knobX - knobSize / 2)
            }
            .animation(.easeInOut(duration: 0.2), value: active)
        }
        .frame(height: 22)
    }
}

// MARK: - Title Overlay

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
