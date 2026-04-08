import SwiftUI

struct LoginView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: LoginViewModel?
    @State private var showQuickConnect = false

    let server: JellyfinServer

    var body: some View {
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
        .onAppear {
            if viewModel == nil {
                viewModel = LoginViewModel(server: server, dependencies: dependencies)
            }
        }
        .onDisappear {
            viewModel?.stopQuickConnect()
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
                Task { await performLogin(vm: vm) }
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
                } else {
                    Button {
                        Task { await performQuickConnectAuth(vm: vm) }
                    } label: {
                        Text("auth.quickConnect.authenticate")
                    }
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

    private func performLogin(vm: LoginViewModel) async {
        guard let (server, user, token) = await vm.login() else { return }
        finalizeAuth(server: server, user: user, token: token)
    }

    private func performQuickConnectAuth(vm: LoginViewModel) async {
        guard let (server, user, token) = await vm.authenticateQuickConnect() else { return }
        finalizeAuth(server: server, user: user, token: token)
    }

    private func finalizeAuth(server: JellyfinServer, user: JellyfinUser, token: String) {
        do {
            try dependencies.saveSession(server: server, token: token)
            appState.setAuthenticated(server: server, user: user)
        } catch {
            viewModel?.errorMessage = error.localizedDescription
        }
    }
}
