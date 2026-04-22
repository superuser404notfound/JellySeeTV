import SwiftUI

/// Playback preferences UI. Each row is a single focusable surface:
/// the Siri Remote's left/right swipe cycles through values directly —
/// no click needed, matching the native tvOS System Settings feel.
struct PlaybackSettingsView: View {
    @Environment(\.dependencies) private var dependencies

    private var prefs: PlaybackPreferences { dependencies.playbackPreferences }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                    .padding(.bottom, 24)

                sectionHeader("settings.playback.section.episodes")

                boolRow(
                    icon: "play.square.stack",
                    title: "settings.playback.autoplayNextEp",
                    subtitle: "settings.playback.autoplayNextEp.subtitle",
                    value: Binding(
                        get: { prefs.autoplayNextEpisode },
                        set: { prefs.autoplayNextEpisode = $0 }
                    )
                )

                boolRow(
                    icon: "forward.end.fill",
                    title: "settings.playback.autoSkipIntro",
                    subtitle: "settings.playback.autoSkipIntro.subtitle",
                    value: Binding(
                        get: { prefs.autoSkipIntro },
                        set: { prefs.autoSkipIntro = $0 }
                    )
                )

                // Next-episode countdown length deliberately not a user
                // setting. Netflix/Prime/Disney+ all hardcode something
                // in the 8–12 s range; users who only saw the "10 s"
                // option in the old picker correctly guessed the other
                // values felt pointless. `autoplayNextEpisode` above is
                // the real knob — on = 10 s countdown then advance,
                // off = overlay stays up until the user picks.

                sectionHeader("settings.playback.section.controls")

                valueRow(
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

                languageRow(
                    icon: "speaker.wave.2",
                    title: "settings.playback.preferredAudio",
                    subtitle: "settings.playback.preferredAudio.subtitle",
                    choices: PlaybackPreferences.audioLanguageChoices,
                    selection: Binding(
                        get: { prefs.preferredAudioLanguage },
                        set: { prefs.preferredAudioLanguage = $0 }
                    )
                )

                languageRow(
                    icon: "captions.bubble",
                    title: "settings.playback.preferredSubtitle",
                    subtitle: "settings.playback.preferredSubtitle.subtitle",
                    choices: PlaybackPreferences.subtitleLanguageChoices,
                    selection: Binding(
                        get: { prefs.preferredSubtitleLanguage },
                        set: { prefs.preferredSubtitleLanguage = $0 }
                    )
                )

                boolRow(
                    icon: "captions.bubble.fill",
                    title: "settings.playback.autoSubtitleForeign",
                    subtitle: "settings.playback.autoSubtitleForeign.subtitle",
                    value: Binding(
                        get: { prefs.autoSubtitleForForeignAudio },
                        set: { prefs.autoSubtitleForForeignAudio = $0 }
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

    private func boolRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        value: Binding<Bool>
    ) -> some View {
        ValuePickerRow(
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

    private func valueRow<Value: Hashable>(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        options: [Value],
        selection: Binding<Value>,
        label: @escaping (Value) -> String
    ) -> some View {
        ValuePickerRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            options: options,
            selection: selection,
            label: label
        )
    }

    private func languageRow(
        icon: String,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        choices: [PlaybackPreferences.LanguageChoice],
        selection: Binding<String?>
    ) -> some View {
        let choiceBinding = Binding<PlaybackPreferences.LanguageChoice>(
            get: { choices.first(where: { $0.code == selection.wrappedValue }) ?? choices[0] },
            set: { selection.wrappedValue = $0.code }
        )
        let labelFn: (PlaybackPreferences.LanguageChoice) -> String = { choice in
            String(localized: String.LocalizationValue(choice.titleKey))
        }
        return ValuePickerRow(
            icon: icon,
            title: title,
            subtitle: subtitle,
            options: choices,
            selection: choiceBinding,
            label: labelFn
        )
    }
}

// MARK: - Value Picker Row

/// Full-width settings row. The Siri Remote's left/right gesture cycles
/// through the options directly — no click, no dropdown to open. The
/// chevrons are visual cues; they're not independent focus targets.
/// Select also advances forward, because some users press instead of
/// swipe. Up/Down moves between rows as usual.
private struct ValuePickerRow<Value: Hashable>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .frame(width: 64)
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

            HStack(spacing: 12) {
                Image(systemName: "chevron.left")
                    .font(.body)
                    .foregroundStyle(focused ? .white : Color.secondary)
                    .opacity(canMoveBackward ? 1 : 0.25)
                Text(label(selection))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(focused ? .white : Color.white.opacity(0.85))
                    .frame(minWidth: 110, alignment: .center)
                    .contentTransition(.opacity)
                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundStyle(focused ? .white : Color.secondary)
                    .opacity(canMoveForward ? 1 : 0.25)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(focused ? Color.white.opacity(0.15) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.tint, lineWidth: 3)
                .opacity(focused ? 1 : 0)
        )
        .scaleEffect(focused ? 1.015 : 1.0)
        .shadow(color: .black.opacity(focused ? 0.3 : 0), radius: 14, y: 6)
        .focusable(true)
        .focused($focused)
        .animation(.easeInOut(duration: 0.15), value: focused)
        .animation(.easeInOut(duration: 0.15), value: selection)
        .onMoveCommand { direction in
            switch direction {
            case .left:  advance(by: -1)
            case .right: advance(by: 1)
            default: break
            }
        }
        // Pressing the clickpad also advances forward for users who
        // prefer clicking over swiping.
        #if os(tvOS)
        .onLongPressGesture(minimumDuration: 0.01) {
            advance(by: 1)
        }
        #endif
    }

    private var currentIndex: Int {
        options.firstIndex(of: selection) ?? 0
    }

    private var canMoveBackward: Bool { currentIndex > 0 }
    private var canMoveForward: Bool { currentIndex < options.count - 1 }

    /// Advance the selection. Clamps at the ends — no wrap — because
    /// wrap is disorienting for short lists like "Off / 5s / 10s / 15s".
    private func advance(by step: Int) {
        let newIdx = max(0, min(options.count - 1, currentIndex + step))
        if newIdx != currentIndex {
            selection = options[newIdx]
        }
    }
}
