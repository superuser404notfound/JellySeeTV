import SwiftUI

/// Playback preferences UI. Rows span the full width of the screen;
/// each option is a focusable chip so the Siri Remote's left/right
/// swipes move between choices without any clicking.
struct PlaybackSettingsView: View {
    @Environment(\.dependencies) private var dependencies

    private var prefs: PlaybackPreferences { dependencies.playbackPreferences }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                    .padding(.bottom, 24)

                sectionHeader("settings.playback.section.episodes")

                boolChipRow(
                    icon: "play.square.stack",
                    title: "settings.playback.autoplayNextEp",
                    subtitle: "settings.playback.autoplayNextEp.subtitle",
                    value: Binding(
                        get: { prefs.autoplayNextEpisode },
                        set: { prefs.autoplayNextEpisode = $0 }
                    )
                )

                chipRow(
                    icon: "timer",
                    title: "settings.playback.nextEpCountdown",
                    subtitle: "settings.playback.nextEpCountdown.subtitle",
                    options: PlaybackPreferences.countdownChoices,
                    selection: Binding(
                        get: { prefs.nextEpisodeCountdownSeconds },
                        set: { prefs.nextEpisodeCountdownSeconds = $0 }
                    ),
                    label: { seconds in
                        seconds == 0
                            ? String(localized: "settings.playback.countdown.off", defaultValue: "Off")
                            : "\(seconds) s"
                    }
                )

                sectionHeader("settings.playback.section.controls")

                chipRow(
                    icon: "goforward",
                    title: "settings.playback.skipInterval",
                    subtitle: "settings.playback.skipInterval.subtitle",
                    options: PlaybackPreferences.skipIntervalChoices,
                    selection: Binding(
                        get: { prefs.skipIntervalSeconds },
                        set: { prefs.skipIntervalSeconds = $0 }
                    ),
                    label: { seconds in "\(seconds) s" }
                )

                sectionHeader("settings.playback.section.languages")

                languageChipRow(
                    icon: "speaker.wave.2",
                    title: "settings.playback.preferredAudio",
                    subtitle: "settings.playback.preferredAudio.subtitle",
                    selection: Binding(
                        get: { prefs.preferredAudioLanguage },
                        set: { prefs.preferredAudioLanguage = $0 }
                    )
                )

                languageChipRow(
                    icon: "captions.bubble",
                    title: "settings.playback.preferredSubtitle",
                    subtitle: "settings.playback.preferredSubtitle.subtitle",
                    selection: Binding(
                        get: { prefs.preferredSubtitleLanguage },
                        set: { prefs.preferredSubtitleLanguage = $0 }
                    )
                )
            }
            .padding(.horizontal, 80)
            .padding(.top, 60)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .toolbar(.hidden, for: .tabBar)
        // Suppress the floating tvOS nav-title; we show our own inline
        // header because the default one sits behind scrolling content.
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var header: some View {
        Text("settings.playback.title")
            .font(.largeTitle)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.top, 24)
            .padding(.bottom, 4)
    }

    // MARK: - Rows

    private func boolChipRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        value: Binding<Bool>
    ) -> some View {
        ChipPickerRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            options: [false, true],
            selection: value,
            label: { on in
                on
                    ? String(localized: "settings.playback.on", defaultValue: "On")
                    : String(localized: "settings.playback.off", defaultValue: "Off")
            }
        )
    }

    private func chipRow<Value: Hashable>(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        options: [Value],
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View {
        ChipPickerRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            options: options,
            selection: selection,
            label: label
        )
    }

    private func languageChipRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        selection: Binding<String?>
    ) -> some View {
        let choices = PlaybackPreferences.languageChoices
        let choiceBinding = Binding<PlaybackPreferences.LanguageChoice>(
            get: { choices.first(where: { $0.code == selection.wrappedValue }) ?? choices[0] },
            set: { selection.wrappedValue = $0.code }
        )
        let labelFn: (PlaybackPreferences.LanguageChoice) -> String = { $0.short }
        return ChipPickerRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            options: choices,
            selection: choiceBinding,
            label: labelFn
        )
    }
}

// MARK: - Chip Picker Row

/// Full-width settings row: icon + title/subtitle on the left, a
/// horizontal row of focusable option chips on the right. Each chip is
/// an independent focusable button, so the tvOS focus engine moves
/// left/right through the options natively — no click needed.
private struct ChipPickerRow<Value: Hashable>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .frame(width: 48)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    OptionChip(
                        label: label(option),
                        isActive: option == selection,
                        action: { selection = option }
                    )
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
        )
    }
}

// MARK: - Option Chip

private struct OptionChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .fontWeight(isActive ? .semibold : .regular)
                .frame(minWidth: 60)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(OptionChipButtonStyle(isActive: isActive))
    }
}

private struct OptionChipButtonStyle: ButtonStyle {
    let isActive: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 2)
            )
            .foregroundStyle(foreground)
            .scaleEffect(isFocused ? 1.08 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 8, y: 3)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private var background: Color {
        if isFocused { return .white.opacity(0.25) }
        if isActive { return Color.accentColor.opacity(0.25) }
        return .white.opacity(0.08)
    }

    private var foreground: Color {
        if isFocused { return .white }
        if isActive { return .white }
        return .white.opacity(0.7)
    }
}
