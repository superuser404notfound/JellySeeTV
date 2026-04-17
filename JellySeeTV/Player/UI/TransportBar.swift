import SwiftUI
import AetherEngine

/// Native tvOS-style transport bar with progress bar, time labels,
/// and track selection buttons with dropdown menus.
///
/// Layout (dropdown open):
/// ```
///                    ┌──────────────┐
///                    │ English  ✓   │
///                    │ German       │
///                    │ Japanese     │
///                    └──────────────┘
///                         [Audio ▲]  [Subs]
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
    let activeAudioIndex: Int?
    let activeSubtitleIndex: Int?
    let controlsFocus: PlayerViewModel.ControlsFocus
    let trackDropdown: PlayerViewModel.TrackDropdown

    var body: some View {
        VStack(spacing: 10) {
            // Scrub time preview
            if isScrubbing {
                Text(scrubTime)
                    .font(.system(size: 56, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .transition(.opacity)
                    .padding(.bottom, 16)
            }

            // Track buttons with dropdown
            if !audioTracks.isEmpty || !subtitleTracks.isEmpty {
                HStack(alignment: .bottom, spacing: 16) {
                    Spacer()

                    if !audioTracks.isEmpty {
                        let activeTrack = audioTracks.first(where: { $0.id == activeAudioIndex })
                        trackButton(
                            label: activeTrack.map { TrackDisplayFormatter.shortName(for: $0) }
                                ?? String(localized: "player.audio", defaultValue: "Audio"),
                            icon: "speaker.wave.2",
                            isFocused: controlsFocus == .audioButton,
                            dropdown: audioDropdownItems,
                            isOpen: isAudioDropdownOpen
                        )
                    }

                    if !subtitleTracks.isEmpty {
                        let activeTrack = activeSubtitleIndex.flatMap { idx in
                            subtitleTracks.first(where: { $0.id == idx })
                        }
                        trackButton(
                            label: activeTrack.map { TrackDisplayFormatter.shortName(for: $0) }
                                ?? String(localized: "player.subtitles.off", defaultValue: "Off"),
                            icon: "captions.bubble",
                            isFocused: controlsFocus == .subtitleButton,
                            dropdown: subtitleDropdownItems,
                            isOpen: isSubtitleDropdownOpen
                        )
                    }
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
        .animation(.easeInOut(duration: 0.15), value: controlsFocus)
        .animation(.easeInOut(duration: 0.15), value: trackDropdown)
    }

    // MARK: - Dropdown State

    private var isAudioDropdownOpen: Bool {
        if case .audio = trackDropdown { return true }
        return false
    }

    private var isSubtitleDropdownOpen: Bool {
        if case .subtitle = trackDropdown { return true }
        return false
    }

    private var audioDropdownItems: [DropdownItem] {
        guard case .audio(let highlighted) = trackDropdown else { return [] }
        return audioTracks.enumerated().map { idx, track in
            DropdownItem(
                title: TrackDisplayFormatter.audioDisplayName(for: track),
                isActive: track.id == activeAudioIndex,
                isHighlighted: idx == highlighted
            )
        }
    }

    private var subtitleDropdownItems: [DropdownItem] {
        guard case .subtitle(let highlighted) = trackDropdown else { return [] }
        var items: [DropdownItem] = [
            DropdownItem(
                title: String(localized: "player.subtitles.off", defaultValue: "Off"),
                isActive: activeSubtitleIndex == nil,
                isHighlighted: highlighted == 0
            )
        ]
        items += subtitleTracks.enumerated().map { idx, track in
            DropdownItem(
                title: TrackDisplayFormatter.subtitleDisplayName(for: track),
                isActive: track.id == activeSubtitleIndex,
                isHighlighted: idx + 1 == highlighted
            )
        }
        return items
    }

    // MARK: - Track Button + Dropdown

    private static let dropdownItemHeight: CGFloat = 40
    private static let dropdownMaxVisible: Int = 8

    private func trackButton(label: String, icon: String, isFocused: Bool, dropdown: [DropdownItem], isOpen: Bool) -> some View {
        VStack(spacing: 6) {
            // Dropdown menu (opens upward, scrollable if many items)
            if isOpen {
                let itemCount = dropdown.count
                let visibleCount = min(itemCount, Self.dropdownMaxVisible)
                let height = CGFloat(visibleCount) * Self.dropdownItemHeight

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(dropdown.enumerated()), id: \.offset) { idx, item in
                                HStack {
                                    Text(item.title)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Spacer()
                                    if item.isActive {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(height: Self.dropdownItemHeight)
                                .background(item.isHighlighted ? Color.white.opacity(0.25) : Color.clear)
                                .foregroundStyle(item.isHighlighted ? .white : .white.opacity(0.8))
                                .id(idx)
                            }
                        }
                    }
                    .onChange(of: dropdown.firstIndex(where: { $0.isHighlighted })) { _, highlighted in
                        if let highlighted {
                            withAnimation { proxy.scrollTo(highlighted, anchor: .center) }
                        }
                    }
                }
                .frame(height: height)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .fixedSize(horizontal: true, vertical: false)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Button label
            Label(label, systemImage: icon)
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
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(.white)
                    .frame(width: knobX, height: trackHeight)

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

// MARK: - Dropdown Item

private struct DropdownItem {
    let title: String
    let isActive: Bool
    let isHighlighted: Bool
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
