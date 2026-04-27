import AppIntents

/// Surfaces our intents to Siri and the Shortcuts app. On tvOS,
/// holding the Siri Remote button and saying any of these phrases
/// invokes the matching intent — Siri matches on the localized
/// phrase from the App Shortcuts catalog, so each language ships
/// its own variant in `Localizable.xcstrings`.
///
/// Apple's docs cap us at 10 phrases per `AppShortcut` and 10
/// shortcuts per provider; we use a fraction of that today to keep
/// the surface focused.
struct JellySeeTVShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenJellySeeTVIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Launch \(.applicationName)",
                "Show \(.applicationName)",
            ],
            shortTitle: "Open",
            systemImageName: "play.tv"
        )
        AppShortcut(
            intent: ContinueWatchingIntent(),
            phrases: [
                "Continue watching on \(.applicationName)",
                "Keep watching on \(.applicationName)",
                "Resume on \(.applicationName)",
                "Resume \(.applicationName)",
            ],
            shortTitle: "Continue Watching",
            systemImageName: "play.fill"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
