import SwiftUI

struct LoginView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: LoginViewModel?
    @State private var showQuickConnect = false
    @State private var showSuccess = false

    let server: JellyfinServer
    /// Pre-selected user from the UserPicker step. `nil` means the
    /// user clicked "Sign in manually" and we show the full form
    /// including the username field.
    var preSelectedUser: JellyfinUser? = nil

    var body: some View {
        ZStack {
            if showSuccess {
                successOverlay
                    .transition(.opacity)
            } else {
                loginContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
        .onAppear {
            if viewModel == nil {
                viewModel = LoginViewModel(
                    server: server,
                    preSelectedUser: preSelectedUser,
                    dependencies: dependencies
                )
            }
        }
        .onDisappear {
            viewModel?.stopQuickConnect()
        }
    }

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

    // Avatar for the pre-selected user — identical composition to the
    // UserPicker card so the transition feels like "same user, now
    // enter password" instead of "different screen."
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
            // Hide the username field when the user was picked from
            // the preceding user-grid — their name is already in the
            // view model and shown above the password field.
            if preSelectedUser == nil {
                TextField(String(localized: "auth.login.username"), text: Bindable(vm).username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
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
                } else {
                    Text("auth.login.signIn")
                }
            }
            .disabled(vm.isLoading || vm.username.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                showQuickConnect = true
                Task { await vm.startQuickConnect() }
            } label: {
                Text("auth.login.quickConnect")
            }
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
            }
        }
        .frame(maxWidth: 500)
    }

    private func showSuccessAndFinalize() {
        guard let vm = viewModel else { return }

        do {
            try vm.finalizeAuth()
        } catch {
            vm.errorMessage = error.localizedDescription
            vm.loginSucceeded = false
            return
        }

        showSuccess = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard let result = vm.authResult else { return }
            appState.setAuthenticated(server: result.server, user: result.user)
        }
    }
}
