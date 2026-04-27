import SwiftUI

@main
struct JellySeeTVApp: App {
    @State private var appState = AppState()
    @State private var dependencies = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(\.appState, appState)
                .environment(\.dependencies, dependencies)
                .preferredColorScheme(.dark)
                .tint(dependencies.appearancePreferences.effectiveTint(
                    isSupporter: dependencies.storeKitService.isSupporter
                ))
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    /// `jellyseetv://item/{id}` is the only scheme we honor today —
    /// emitted by the TopShelf extension's cell `displayAction`.
    /// Stash the id in AppState; AppRouter watches that field, fetches
    /// the full item, and presents the detail sheet once the session
    /// has finished restoring on cold launches.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "jellyseetv", url.host == "item" else { return }
        let id = url.pathComponents.dropFirst().first ?? ""
        guard !id.isEmpty else { return }
        appState.pendingDeepLinkItemID = id
    }
}
