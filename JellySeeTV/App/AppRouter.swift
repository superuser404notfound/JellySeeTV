import SwiftUI

struct AppRouter: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    /// Tracks whether the initial session restore + splash has already
    /// run for this process. SwiftUI re-fires `.task` when the AppRouter
    /// view temporarily disappears (e.g. while the UIKit-presented
    /// player modal is on screen) — without this guard, returning from
    /// the player would show the launch splash again.
    @State private var hasRestored = false

    var body: some View {
        ZStack {
            if appState.isAuthenticated {
                TabRootView()
            } else {
                ServerDiscoveryView()
            }

            // Splash overlays everything until both the session restore
            // has finished AND the minimum display time has elapsed —
            // then it fades out to reveal whichever root view is now
            // appropriate. Cross-fade looks nicer than the old spinner-
            // then-content swap and prevents a jarring snap when restore
            // completes in <100 ms.
            if appState.isLoading {
                SplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: appState.isLoading)
        .task {
            guard !hasRestored else { return }
            hasRestored = true
            await restoreSession()
        }
    }

    private func restoreSession() async {
        appState.isLoading = true
        let splashStart = Date()
        await performRestore()

        // Hold the splash for at least the minimum so the brand moment
        // isn't reduced to a flash on a fast restore path.
        let elapsed = Date().timeIntervalSince(splashStart)
        let remaining = SplashView.minimumDisplayDuration - elapsed
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        appState.isLoading = false
    }

    private func performRestore() async {
        guard dependencies.restoreSession() else { return }

        guard let serverData = try? dependencies.keychainService.loadData(for: "activeServer"),
              let server = try? JSONDecoder().decode(JellyfinServer.self, from: serverData),
              let userID = try? dependencies.keychainService.loadString(for: KeychainKeys.userID(serverID: server.id)),
              let userName = try? dependencies.keychainService.loadString(for: "activeUserName")
        else {
            try? dependencies.clearSession()
            return
        }

        let user = JellyfinUser(
            id: userID,
            name: userName,
            serverID: server.id,
            hasPassword: nil,
            primaryImageTag: nil
        )
        appState.setAuthenticated(server: server, user: user)

        if let seerrServer = dependencies.restoreSeerrSession() {
            if let seerrUser = try? await dependencies.seerrAuthService.currentUser() {
                appState.setSeerrConnected(server: seerrServer, user: seerrUser)
            } else {
                try? dependencies.clearSeerrSession()
            }
        }
    }
}
