import AppIntents
import Foundation

// MARK: - Open App

/// Bare-bones launcher used as the foundation phrase for App
/// Shortcuts. Surfaces "Open JellySeeTV" / "JellySeeTV öffnen" in
/// Siri suggestions and the Shortcuts app even before any other
/// intent ships.
struct OpenJellySeeTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Open JellySeeTV"
    static let description = IntentDescription("Open the JellySeeTV app.")
    static let openAppWhenRun: Bool = true
    /// `.alwaysAllowed` lets tvOS-Siri voice-invoke the intent
    /// without the device-unlock prompt. The action is harmless —
    /// just opens the app — and Siri otherwise refuses with
    /// "die App unterstützt diesen Vorgang mit Siri nicht."
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Continue Watching

/// Resumes the most recent Resume-queue item. Reuses the same
/// `pendingDeepLinkItemID` channel as the TopShelf cell taps —
/// `AppRouter` already watches that field, fetches the item, and
/// presents `DetailRouterView` over the tab root.
///
/// Siri-via-tvOS-remote rejects intents whose `perform()` does
/// async work (network, long waits) on the assumption they need
/// authentication. We sidestep that by flipping a boolean on
/// `AppState`, returning immediately, and letting `AppRouter` do
/// the resume-fetch + navigation in normal app context. From
/// Siri's point of view the intent is now a trivial state mutation.
struct ContinueWatchingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Watching"
    static let description = IntentDescription("Resume your most recent show or movie on JellySeeTV.")
    static let openAppWhenRun: Bool = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentBridge.appState?.requestContinueWatching = true
        return .result()
    }
}
