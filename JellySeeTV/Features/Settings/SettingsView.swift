import SwiftUI

struct SettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            if let user = appState.activeUser {
                Text(user.name)
                    .font(.headline)
            }

            if let server = appState.activeServer {
                Text(server.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                try? dependencies.clearSession()
                appState.logout()
            } label: {
                Text("settings.logout")
            }

            Spacer()
        }
    }
}
