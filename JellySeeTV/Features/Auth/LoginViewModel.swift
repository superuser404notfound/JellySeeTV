import Foundation
import Observation

@Observable
final class LoginViewModel {
    var username = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?

    // Quick Connect
    var quickConnectCode: String?
    var isPollingQuickConnect = false

    let server: JellyfinServer

    private let authService: JellyfinAuthServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let dependencies: DependencyContainer
    private var quickConnectSecret: String?
    private var quickConnectTask: Task<Void, Never>?

    init(
        server: JellyfinServer,
        dependencies: DependencyContainer
    ) {
        self.server = server
        self.authService = dependencies.jellyfinAuthService
        self.keychainService = dependencies.keychainService
        self.dependencies = dependencies
    }

    func login() async -> (JellyfinServer, JellyfinUser, String)? {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await authService.login(username: username, password: password)
            isLoading = false
            return (server, response.user, response.accessToken)
        } catch let error as APIError {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        }
    }

    func startQuickConnect() async {
        errorMessage = nil

        do {
            let response = try await authService.initiateQuickConnect()
            quickConnectCode = response.code
            quickConnectSecret = response.secret
            isPollingQuickConnect = true
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopQuickConnect() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        isPollingQuickConnect = false
        quickConnectCode = nil
        quickConnectSecret = nil
    }

    private func startPolling() {
        quickConnectTask?.cancel()
        quickConnectTask = Task { [weak self] in
            guard let self, let secret = self.quickConnectSecret else { return }

            while !Task.isCancelled && self.isPollingQuickConnect {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }

                do {
                    let isAuthorized = try await self.authService.checkQuickConnect(secret: secret)
                    if isAuthorized {
                        self.isPollingQuickConnect = false
                        return
                    }
                } catch {
                    // Continue polling on error
                }
            }
        }
    }

    func authenticateQuickConnect() async -> (JellyfinServer, JellyfinUser, String)? {
        guard let secret = quickConnectSecret else { return nil }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await authService.authenticateWithQuickConnect(secret: secret)
            isLoading = false
            stopQuickConnect()
            return (server, response.user, response.accessToken)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return nil
        }
    }

    deinit {
        quickConnectTask?.cancel()
    }
}
