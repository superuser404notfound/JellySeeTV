import SwiftUI

struct LoginView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: LoginViewModel?
    @State private var showQuickConnect = false
    @State private var showSuccess = false
    #if os(iOS)
    @Environment(\.appearanceTheme) private var appearanceTheme
    @State private var promptServer: JellyfinServer?
    @State private var showAddURLDialog = false
    @State private var showAddURLSheet = false
    #endif

    let server: JellyfinServer
    /// Nil means "Sign in manually": show the full form including the username field.
    var preSelectedUser: JellyfinUser? = nil
    var addMode: Bool = false
    var onCompletion: (() -> Void)? = nil

    var body: some View {
        ZStack {
            if showSuccess {
                successOverlay
                    .transition(.opacity)
            } else {
                loginContent
                    .transition(.opacity)
            }
            #if os(iOS)
            if showAddURLDialog {
                addURLPromptOverlay
                    .transition(.opacity)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
        #if os(iOS)
        .animation(.easeInOut(duration: 0.25), value: showAddURLDialog)
        #endif
        .onAppear {
            if viewModel == nil {
                viewModel = LoginViewModel(
                    server: server,
                    preSelectedUser: preSelectedUser,
                    dependencies: dependencies
                )
            }
        }
        .task {
            // The view model pins an optimistic address in its init so the first frame has one; this
            // is the probe that corrects it. Reached directly (a server with one profile, a deep
            // link) the picker's own resolve never ran, and without this the sign-in would spend its
            // whole life on the last route that worked, which away from home is the LAN address.
            await dependencies.resolveSignInRoute(for: server)
        }
        .onDisappear {
            viewModel?.stopQuickConnect()
        }
        #if os(iOS)
        .sheet(isPresented: $showAddURLSheet, onDismiss: { proceedAfterAuth() }) {
            if let server = promptServer, let slot = server.emptyURLSlot {
                AddSecondURLSheet(
                    slot: slot,
                    knownURL: server.url,
                    resolve: ServerAddressResolution.jellyfin(dependencies.serverDiscoveryService),
                    onSave: { newURL in
                        let merged = server.urls(filling: slot, with: newURL)
                        try? dependencies.updateServerURLs(
                            serverID: server.id,
                            internalURL: merged.internal,
                            externalURL: merged.external
                        )
                    }
                )
            }
        }
        #endif
    }

    #if os(iOS)
    private var addURLDialogTitle: LocalizedStringKey {
        guard let slot = promptServer?.emptyURLSlot else { return "" }
        return slot == .internal
            ? "multiServer.addURL.dialog.title.internal"
            : "multiServer.addURL.dialog.title.external"
    }

    private var addURLPromptOverlay: some View {
        ZStack {
            Color.Theme.scrim
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text(addURLDialogTitle, bundle: .main)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text("multiServer.addURL.dialog.message", bundle: .main)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    Button {
                        showAddURLSheet = true
                    } label: {
                        Text("multiServer.addURL.dialog.add", bundle: .main)
                            .font(.headline)
                            .foregroundStyle(appearanceTheme.palette.foreground.color)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Button {
                        proceedAfterAuth()
                    } label: {
                        Text("multiServer.addURL.dialog.notNow", bundle: .main)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(32)
        }
    }
    #endif

    private var loginContent: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 12) {
                if let preSelectedUser {
                    userAvatar(for: preSelectedUser)
                }

                Text(preSelectedUser?.name ?? server.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("auth.login.subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if let vm = viewModel {
                if showQuickConnect {
                    quickConnectSection(vm: vm)
                } else {
                    loginFormSection(vm: vm)
                }
            }

            Spacer()
        }
        .padding()
        .onChange(of: viewModel?.loginSucceeded) { _, succeeded in
            if succeeded == true {
                showSuccessAndFinalize()
            }
        }
    }

    // Identical composition to the UserPicker card so the transition reads as "same user, now enter password".
    @ViewBuilder
    private func userAvatar(for user: JellyfinUser) -> some View {
        let url = dependencies.jellyfinImageService.userProfileImageURL(
            userID: user.id,
            tag: user.primaryImageTag
        )
        ZStack {
            if let url {
                AsyncCachedImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsCircle(for: user.name)
                }
                .frame(width: 140, height: 140)
                .clipShape(Circle())
            } else {
                initialsCircle(for: user.name)
                    .frame(width: 140, height: 140)
            }
        }
    }

    private func initialsCircle(for name: String) -> some View {
        let parts = name.split(separator: " ")
        let initials: String = {
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }()
        return ZStack {
            Circle().fill(.ultraThinMaterial)
            Text(initials)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private var successOverlay: some View {
        VStack(spacing: 24) {
            Spacer()
            CheckmarkAnimation()
            if let user = viewModel?.authResult?.user {
                Text("auth.login.welcome \(user.name)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func loginFormSection(vm: LoginViewModel) -> some View {
        VStack(spacing: 20) {
            // Username already shown above when picked from the user-grid.
            if preSelectedUser == nil {
                TextField(String(localized: "auth.login.username"), text: Bindable(vm).username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            SecureField(String(localized: "auth.login.password"), text: Bindable(vm).password)

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await vm.login() }
            } label: {
                if vm.isLoading {
                    ProgressView()
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                } else {
                    Text("auth.login.signIn")
                        .font(.body)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                }
            }
            // Primary action; Quick Connect below stays secondary.
            .buttonStyle(SettingsTileButtonStyle(isProminent: true))
            .disabled(vm.isLoading || vm.username.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                showQuickConnect = true
                Task { await vm.startQuickConnect() }
            } label: {
                Text("auth.login.quickConnect")
                    .font(.body)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
            .buttonStyle(SettingsTileButtonStyle())
        }
        .frame(maxWidth: 500)
    }

    @ViewBuilder
    private func quickConnectSection(vm: LoginViewModel) -> some View {
        VStack(spacing: 20) {
            Text("auth.quickConnect.title")
                .font(.title3)

            if let code = vm.quickConnectCode {
                Text("auth.quickConnect.instruction")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(code)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .padding()

                if vm.isPollingQuickConnect {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("auth.quickConnect.waiting")
                            .foregroundStyle(.secondary)
                    }
                } else if vm.isLoading {
                    ProgressView()
                }
            } else {
                ProgressView()
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                vm.stopQuickConnect()
                showQuickConnect = false
            } label: {
                Text("auth.quickConnect.cancel")
                    .font(.body)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
            .buttonStyle(SettingsTileButtonStyle())
        }
        .frame(maxWidth: 500)
    }

    private func showSuccessAndFinalize() {
        guard let vm = viewModel else { return }

        do {
            try vm.finalizeAuth()
        } catch {
            vm.errorMessage = ErrorText.user(for: error)
            vm.loginSucceeded = false
            return
        }

        showSuccess = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard let result = vm.authResult else { return }

            #if os(iOS)
            // Offer the missing internal/external URL once per server, before the
            // authenticated root swap so LoginView stays mounted for the prompt.
            if result.server.emptyURLSlot != nil,
               !DualURLPromptLatch.hasOffered(serverID: result.server.id) {
                DualURLPromptLatch.markOffered(serverID: result.server.id)
                promptServer = result.server
                withAnimation { showAddURLDialog = true }
                return
            }
            #endif

            proceedAfterAuth()
        }
    }

    private func proceedAfterAuth() {
        guard let result = viewModel?.authResult else { return }

        #if os(iOS)
        showAddURLDialog = false
        #endif

        // Persistence already happened in finalizeAuth -> saveSession; old addServer/pointer writes here were no-ops.
        appState.setAuthenticated(server: result.server, user: result.user)

        Task {
            // Re-evaluate Seerr against the new user. Add-mode needs this too, else it inherits the previous profile's Seerr state.
            await syncSeerrToActiveProfile(
                userID: result.user.id,
                serverID: result.server.id
            )

            // Needed by the "Add another profile" branch (stays mounted on TabRootView until popped); first-run relies on AppRouter swapping its root on isAuthenticated.
            NotificationCenter.default.post(name: .loginDidComplete, object: nil)

            // Add-mode hook (refresh Settings server list); nil in first-run.
            onCompletion?()
        }
    }

    /// Restores the just-authed profile's Seerr session from keychain (or wipes it). Mirrors ProfileSettingsView.restoreSeerrForSwitchedProfile.
    private func syncSeerrToActiveProfile(userID: String, serverID: String) async {
        let outcome = await dependencies.syncSeerrSession(
            forJellyfinUserID: userID,
            jellyfinServerID: serverID
        )
        if case .connected(let server, let user) = outcome {
            appState.setSeerrConnected(server: server, user: user)
            dependencies.scheduleRouteResolve()
        } else {
            appState.disconnectSeerr()
        }
    }
}
