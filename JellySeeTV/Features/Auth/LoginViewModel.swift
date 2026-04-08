import Foundation
import Observation

@Observable
final class LoginViewModel {
    var username = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?
    var loginSucceeded = false

    // Quick Connect
    var quickConnectCode: String?
    var isPollingQuickConnect = false
    var quickConnectAuthorized = false

    // Auth result stored for finalization after animation
    var authResult: (server: JellyfinServer, user: JellyfinUser, token: String)?

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
        dependencies.jellyfinClient.baseURL = server.url
    }

    func login() async {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await authService.login(username: username, password: password)
            authResult = (server, response.user, response.accessToken)
            isLoading = false
            loginSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
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
        quickConnectAuthorized = false
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
                        self.quickConnectAuthorized = true
                        await self.authenticateQuickConnect()
                        return
                    }
                } catch {
                    // Continue polling on error
                }
            }
        }
    }

    private func authenticateQuickConnect() async {
        guard let secret = quickConnectSecret else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await authService.authenticateWithQuickConnect(secret: secret)
            authResult = (server, response.user, response.accessToken)
            isLoading = false
            loginSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func finalizeAuth() throws {
        guard let result = authResult else { return }
        try dependencies.saveSession(server: result.server, user: result.user, token: result.token)
    }

    nonisolated deinit {
        // Task cleanup happens automatically when the ViewModel is deallocated
    }
}
