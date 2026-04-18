import SwiftUI

struct SeerrSettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    @State private var serverAddressText: String = ""
    @State private var isDiscovering = false
    @State private var discoveredServer: SeerrServer?
    @State private var serverVersion: String?
    @State private var discoveryError: String?

    @State private var useJellyfinCredentials = true
    @State private var usernameText: String = ""
    @State private var passwordText: String = ""
    @State private var isLoggingIn = false
    @State private var loginError: String?

    @State private var showSuccess = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 32) {
                    header

                    if appState.isSeerrConnected {
                        connectedState
                    } else {
                        serverSection
                        if discoveredServer != nil {
                            credentialsSection
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.vertical, 60)
                .padding(.horizontal, 80)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
            .animation(.easeInOut(duration: 0.3), value: discoveredServer)
            .animation(.easeInOut(duration: 0.3), value: appState.isSeerrConnected)

            if showSuccess {
                successOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
        .navigationTitle(Text("settings.seerr.title"))
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: bootstrap)
    }

    // MARK: - Sections

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

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.seerr.section.server")
                .font(.headline)

            if let server = discoveredServer {
                discoveredServerCard(server: server)
            } else {
                VStack(spacing: 12) {
                    TextField(
                        String(localized: "settings.seerr.serverAddress.placeholder",
                               defaultValue: "IP or URL"),
                        text: $serverAddressText
                    )
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                    if let discoveryError {
                        Text(discoveryError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await discover() }
                    } label: {
                        if isDiscovering {
                            ProgressView()
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                        } else {
                            Text("settings.seerr.connect")
                                .font(.body)
                                .fontWeight(.medium)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                        }
                    }
                    .disabled(isDiscovering || !isAddressValid)
                }
            }
        }
    }

    private func discoveredServerCard(server: SeerrServer) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.url.host ?? server.url.absoluteString)
                    .font(.body)
                    .fontWeight(.medium)
                if let serverVersion {
                    Text(verbatim: "v\(serverVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                discoveredServer = nil
                serverVersion = nil
                loginError = nil
                passwordText = ""
            } label: {
                Text("settings.seerr.changeServer")
                    .font(.caption)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.seerr.section.credentials")
                .font(.headline)

            if hasJellyfinUser {
                Toggle(isOn: $useJellyfinCredentials) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.seerr.useJellyfin")
                            .font(.body)
                        Text("settings.seerr.useJellyfin.subtitle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: useJellyfinCredentials) { _, newValue in
                    if newValue, let jfName = appState.activeUser?.name {
                        usernameText = jfName
                    }
                }
            }

            VStack(spacing: 12) {
                TextField(
                    String(localized: "auth.login.username", defaultValue: "Username"),
                    text: $usernameText
                )
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disabled(useJellyfinCredentials && hasJellyfinUser)
                .opacity(useJellyfinCredentials && hasJellyfinUser ? 0.6 : 1.0)

                SecureField(
                    String(localized: "auth.login.password", defaultValue: "Password"),
                    text: $passwordText
                )

                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                            .fontWeight(.semibold)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                    }
                }
                .disabled(isLoggingIn || !isCredentialsValid)
            }
        }
    }

    private var connectedState: some View {
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.activeSeerrUser?.resolvedDisplayName ?? "")
                        .font(.body)
                        .fontWeight(.medium)
                    Text(appState.activeSeerrServer?.url.host ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)
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

    private var successOverlay: some View {
        VStack(spacing: 24) {
            Spacer()
            CheckmarkAnimation()
            Text("settings.seerr.success")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Derived

    private var isAddressValid: Bool {
        !serverAddressText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isCredentialsValid: Bool {
        !usernameText.trimmingCharacters(in: .whitespaces).isEmpty
            && !passwordText.isEmpty
    }

    private var hasJellyfinUser: Bool {
        appState.activeUser != nil
    }

    // MARK: - Actions

    private func bootstrap() {
        if let jfName = appState.activeUser?.name, usernameText.isEmpty {
            usernameText = jfName
        }
    }

    private func discover() async {
        let input = serverAddressText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        isDiscovering = true
        discoveryError = nil
        defer { isDiscovering = false }

        let result = await dependencies.seerrServerDiscoveryService.discoverServer(input: input)

        switch result {
        case .success(let url, let info):
            let server = SeerrServer(url: url)
            dependencies.seerrClient.baseURL = url
            discoveredServer = server
            serverVersion = info.version
        case .failure(let error):
            discoveryError = error.localizedDescription
        }
    }

    private func login() async {
        guard let server = discoveredServer,
              let jellyfinURL = appState.activeServer?.url
        else {
            loginError = String(
                localized: "settings.seerr.error.missingJellyfin",
                defaultValue: "Sign in to Jellyfin first."
            )
            return
        }

        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        let username = usernameText.trimmingCharacters(in: .whitespaces)

        do {
            let user = try await dependencies.seerrAuthService.loginWithJellyfin(
                username: username,
                password: passwordText,
                jellyfinURL: jellyfinURL
            )
            try dependencies.saveSeerrSession(server: server)
            passwordText = ""
            showSuccess = true

            try? await Task.sleep(for: .seconds(1.5))
            appState.setSeerrConnected(server: server, user: user)
            showSuccess = false
        } catch {
            try? dependencies.clearSeerrSession()
            loginError = error.localizedDescription
        }
    }

    private func logout() async {
        do {
            try await dependencies.seerrAuthService.logout()
        } catch {
        }
        try? dependencies.clearSeerrSession()
        appState.disconnectSeerr()
        discoveredServer = nil
        serverVersion = nil
        serverAddressText = ""
        passwordText = ""
    }
}
