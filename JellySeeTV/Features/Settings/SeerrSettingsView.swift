import SwiftUI

struct SeerrSettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var serverURLText: String = ""
    @State private var passwordText: String = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case url, password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                header

                if appState.isSeerrConnected {
                    connectedState
                } else {
                    loginForm
                }
            }
            .padding(.vertical, 60)
            .padding(.horizontal, 80)
        }
        .navigationTitle(Text("settings.seerr.title"))
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let server = appState.activeSeerrServer {
                serverURLText = server.url.absoluteString
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("settings.seerr.title")
                .font(.title2)
                .fontWeight(.semibold)
            Text("settings.seerr.description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var connectedState: some View {
        VStack(spacing: 20) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.activeSeerrUser?.resolvedDisplayName ?? "")
                        .font(.body)
                        .fontWeight(.medium)
                    Text(appState.activeSeerrServer?.url.host ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.05))
            )

            Button {
                Task { await logout() }
            } label: {
                Label("settings.seerr.logout", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.body)
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
        }
    }

    private var loginForm: some View {
        VStack(spacing: 20) {
            TextField(
                String(localized: "settings.seerr.serverURL", defaultValue: "Server URL"),
                text: $serverURLText
            )
            .textContentType(.URL)
            .focused($focusedField, equals: .url)

            SecureField(
                String(localized: "settings.seerr.jellyfinPassword", defaultValue: "Jellyfin Password"),
                text: $passwordText
            )
            .textContentType(.password)
            .focused($focusedField, equals: .password)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await login() }
            } label: {
                if isLoggingIn {
                    ProgressView()
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                } else {
                    Text("settings.seerr.login")
                        .font(.body)
                        .fontWeight(.medium)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                }
            }
            .disabled(isLoggingIn || !isFormValid)
        }
        .frame(maxWidth: 600)
    }

    private var isFormValid: Bool {
        URL(string: serverURLText.trimmingCharacters(in: .whitespaces))?.host != nil
            && !passwordText.isEmpty
    }

    private func login() async {
        guard let url = URL(string: serverURLText.trimmingCharacters(in: .whitespaces)),
              let jellyfinURL = appState.activeServer?.url,
              let username = appState.activeUser?.name
        else {
            errorMessage = String(localized: "settings.seerr.error.missingJellyfin",
                                  defaultValue: "Sign in to Jellyfin first.")
            return
        }

        isLoggingIn = true
        errorMessage = nil
        defer { isLoggingIn = false }

        let server = SeerrServer(url: url)
        dependencies.seerrClient.baseURL = url

        do {
            let user = try await dependencies.seerrAuthService.loginWithJellyfin(
                username: username,
                password: passwordText,
                jellyfinURL: jellyfinURL
            )
            try dependencies.saveSeerrSession(server: server)
            appState.setSeerrConnected(server: server, user: user)
            passwordText = ""
        } catch {
            try? dependencies.clearSeerrSession()
            errorMessage = error.localizedDescription
        }
    }

    private func logout() async {
        do {
            try await dependencies.seerrAuthService.logout()
        } catch {
        }
        try? dependencies.clearSeerrSession()
        appState.disconnectSeerr()
    }
}
