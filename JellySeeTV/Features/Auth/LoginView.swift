import SwiftUI

struct LoginView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: LoginViewModel?
    @State private var showQuickConnect = false
    @State private var showSuccess = false

    let server: JellyfinServer

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
                viewModel = LoginViewModel(server: server, dependencies: dependencies)
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
                Text(server.name)
                    .font(.title2)

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
            TextField(String(localized: "auth.login.username"), text: Bindable(vm).username)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif

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
