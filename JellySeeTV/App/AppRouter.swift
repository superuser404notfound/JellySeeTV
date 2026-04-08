import SwiftUI

struct AppRouter: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        Group {
            if appState.isLoading {
                ProgressView()
            } else if appState.isAuthenticated {
                TabRootView()
            } else {
                ServerDiscoveryView()
            }
        }
        .task {
            await restoreSession()
        }
    }

    private func restoreSession() async {
        appState.isLoading = true
        defer { appState.isLoading = false }

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
    }
}
