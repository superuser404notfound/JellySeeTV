import SwiftUI

/// Playback preferences UI. Rows mirror `SettingsTile` visually so the
/// Settings tab feels consistent, but use inline pickers instead of
/// NavigationLink since every choice is immediate and few.
struct PlaybackSettingsView: View {
    @Environment(\.dependencies) private var dependencies

    private var prefs: PlaybackPreferences { dependencies.playbackPreferences }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sectionHeader("settings.playback.section.episodes")

                toggleRow(
                    icon: "play.square.stack",
                    title: "settings.playback.autoplayNextEp",
                    subtitle: "settings.playback.autoplayNextEp.subtitle",
                    value: Binding(
                        get: { prefs.autoplayNextEpisode },
                        set: { prefs.autoplayNextEpisode = $0 }
                    )
                )

                pickerRow(
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

                pickerRow(
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

                languagePickerRow(
                    icon: "speaker.wave.2",
                    title: "settings.playback.preferredAudio",
                    subtitle: "settings.playback.preferredAudio.subtitle",
                    selection: Binding(
                        get: { prefs.preferredAudioLanguage },
                        set: { prefs.preferredAudioLanguage = $0 }
                    )
                )

                languagePickerRow(
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
            .padding(.top, 40)
            .padding(.bottom, 60)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("settings.playback.title")
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Rows

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
    }

    private func toggleRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        value: Binding<Bool>
    ) -> some View {
        Button {
            value.wrappedValue.toggle()
        } label: {
            settingsRowContent(icon: icon, title: title, subtitle: subtitle) {
                Image(systemName: value.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(value.wrappedValue ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private func pickerRow<Value: Hashable>(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        options: [Value],
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View {
        SegmentedPickerRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            options: options,
            selection: selection,
            label: label
        )
    }

    private func languagePickerRow(
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
        let labelFn: (PlaybackPreferences.LanguageChoice) -> String = { choice in
            String(localized: String.LocalizationValue(choice.titleKey))
        }
        return SegmentedPickerRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            options: choices,
            selection: choiceBinding,
            label: labelFn
        )
    }

    private func settingsRowContent<Trailing: View>(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
            trailing()
        }
        .padding(20)
    }
}

// MARK: - Segmented Picker Row

/// Single-row picker for short finite choice lists. The row itself holds
/// focus and cycles through options on select — cleaner than a separate
/// NavigationLink for settings with 3-5 values.
private struct SegmentedPickerRow<Value: Hashable>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        Button {
            advance()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(label(selection))
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(minWidth: 80, alignment: .center)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }

    private func advance() {
        guard let current = options.firstIndex(of: selection) else {
            selection = options.first ?? selection
            return
        }
        let next = (current + 1) % options.count
        selection = options[next]
    }
}

// MARK: - Button Style

struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFocused ? .white.opacity(0.15) : .white.opacity(0.05))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 10, y: 4)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
