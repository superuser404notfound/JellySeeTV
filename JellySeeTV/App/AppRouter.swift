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

        // Validate that the token is still valid
        do {
            let serverInfo = try await dependencies.jellyfinClient.request(
                endpoint: JellyfinEndpoint.publicInfo,
                responseType: JellyfinPublicServerInfo.self
            )

            if let serverData = try? dependencies.keychainService.loadData(for: "activeServer"),
               let server = try? JSONDecoder().decode(JellyfinServer.self, from: serverData) {
                let updatedServer = JellyfinServer(
                    id: server.id,
                    name: serverInfo.serverName,
                    url: server.url,
                    version: serverInfo.version
                )
                appState.setAuthenticated(server: updatedServer, user: JellyfinUser(
                    id: "",
                    name: "",
                    serverID: server.id,
                    hasPassword: nil,
                    primaryImageTag: nil
                ))
            }
        } catch {
            try? dependencies.clearSession()
        }
    }
}
