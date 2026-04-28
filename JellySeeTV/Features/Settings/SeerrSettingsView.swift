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
    @State private var cachedJellyfinPassword: String?
    @State private var isLoggingIn = false
    @State private var loginError: String?

    @State private var showSuccess = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 32) {
                    Text("settings.seerr.title")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)

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
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .padding(.horizontal, 80)
            }
            .animation(.easeInOut(duration: 0.3), value: discoveredServer)
            .animation(.easeInOut(duration: 0.3), value: appState.isSeerrConnected)

            if showSuccess {
                successOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
        .toolbar(.hidden, for: .tabBar)
        // Inline header only — the floating tvOS nav-title sits behind
        // the scrolling content and looks like a ghost when the user
        // scrolls past it. Matches PlaybackSettingsView.
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: bootstrap)
    }

    // MARK: - Server Section

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.seerr.section.server")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let server = discoveredServer {
                discoveredServerCard(server: server)
            } else {
                serverEntry
            }
        }
    }

    private var serverEntry: some View {
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

            if let jellyfinHost = appState.activeServer?.url.host {
                Button {
                    serverAddressText = jellyfinHost
                } label: {
                    Label("settings.seerr.useJellyfinIP", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        // Keep the label readable when a custom accent
                        // tint is active — without this, the bordered
                        // button would render icon + text in the same
                        // tint colour as its fill.
                        .foregroundStyle(.primary)
                }
            }

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

    // MARK: - Credentials Section

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.seerr.section.credentials")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasJellyfinUser {
                jellyfinToggle
            }

            VStack(spacing: 12) {
                if !isUsernameHidden {
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
                }

                if isPasswordHidden {
                    passwordCachedNote
                } else {
                    if useJellyfinCredentials && hasJellyfinUser && cachedJellyfinPassword == nil {
                        quickConnectNote
                    }
                    SecureField(
                        String(localized: "auth.login.password", defaultValue: "Password"),
                        text: $passwordText
                    )
                }

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
                .disabled(isLoggingIn || !canSubmit)
            }
        }
    }

    private var jellyfinToggle: some View {
        Button {
            useJellyfinCredentials.toggle()
            if useJellyfinCredentials, let jfName = appState.activeUser?.name {
                usernameText = jfName
            }
            passwordText = ""
            loginError = nil
        } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.seerr.useJellyfin")
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("settings.seerr.useJellyfin.subtitle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(useJellyfinCredentials ? "common.on" : "common.off")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(useJellyfinCredentials ? Color.green : Color.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(useJellyfinCredentials ? Color.green.opacity(0.15) : Color.white.opacity(0.08))
                    )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    private var passwordCachedNote: some View {
        Label {
            Text("settings.seerr.passwordCached")
                .font(.caption)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.08))
        )
    }

    private var quickConnectNote: some View {
        Label {
            Text("settings.seerr.quickConnectNote")
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.04))
        )
    }

    // MARK: - Connected State

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
            .buttonStyle(SettingsTileButtonStyle())
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

    private var hasJellyfinUser: Bool {
        appState.activeUser != nil
    }

    private var isUsernameHidden: Bool {
        useJellyfinCredentials && hasJellyfinUser
    }

    private var isPasswordHidden: Bool {
        useJellyfinCredentials && hasJellyfinUser && cachedJellyfinPassword != nil
    }

    private var canSubmit: Bool {
        guard !isLoggingIn else { return false }
        if usernameText.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if isPasswordHidden { return true }
        return !passwordText.isEmpty
    }

    // MARK: - Actions

    private func bootstrap() {
        if let jfName = appState.activeUser?.name, usernameText.isEmpty {
            usernameText = jfName
        }
        cachedJellyfinPassword = dependencies.loadJellyfinPassword()
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
        guard let server = discoveredServer else { return }

        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        let username = usernameText.trimmingCharacters(in: .whitespaces)
        let password: String = {
            if isPasswordHidden, let cached = cachedJellyfinPassword {
                return cached
            }
            return passwordText
        }()

        do {
            let user = try await dependencies.seerrAuthService.loginWithJellyfin(
                username: username,
                password: password
            )
            // Tie the Seerr session to the currently active Jellyfin
            // profile so a future switchToUser can restore it without
            // the user re-authenticating.
            try dependencies.saveSeerrSession(
                server: server,
                forJellyfinUserID: appState.activeUser?.id,
                jellyfinServerID: appState.activeServer?.id
            )
            passwordText = ""
            showSuccess = true

            try? await Task.sleep(for: .seconds(1.5))
            appState.setSeerrConnected(server: server, user: user)
            showSuccess = false
        } catch {
            // Drop the session cookie only — keep the discovered baseURL so
            // the user can retry without re-entering the server address.
            // Full clearSeerrSession() would wipe baseURL and the next
            // attempt would fail with "invalid URL" before even reaching
            // the server.
            dependencies.seerrClient.sessionCookie = nil
            loginError = error.localizedDescription
        }
    }

    private func logout() async {
        do {
            try await dependencies.seerrAuthService.logout()
        } catch {
            #if DEBUG
            print("[SeerrSettings] remote logout failed (clearing local session anyway): \(error)")
            #endif
        }
        try? dependencies.clearSeerrSession()
        appState.disconnectSeerr()
        discoveredServer = nil
        serverVersion = nil
        serverAddressText = ""
        passwordText = ""
    }
}
