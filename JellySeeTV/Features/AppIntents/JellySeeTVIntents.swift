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
/// Failure modes (no session, server unreachable, empty queue) just
/// surface as "the app opened on Home and nothing happened" — Siri
/// has no graceful retry surface and a user-facing error toast for
/// a voice command would be more annoying than the silent fall-back.
struct ContinueWatchingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Watching"
    static let description = IntentDescription("Resume your most recent show or movie on JellySeeTV.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = IntentBridge.appState,
              let dependencies = IntentBridge.dependencies
        else {
            return .result()
        }

        // Cold launches: AppRouter's restoreSession runs in parallel
        // with this perform() call. Wait up to 5s for auth so a
        // siri-from-locked-tv flow still finds an active user.
        var waited = 0
        while !appState.isAuthenticated, waited < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        guard let user = appState.activeUser else { return .result() }

        let response = try? await dependencies.jellyfinLibraryService.getResumeItems(
            userID: user.id,
            mediaType: "Video",
            limit: 1
        )
        if let item = response?.items.first {
            appState.pendingDeepLinkItemID = item.id
        }
        return .result()
    }
}
