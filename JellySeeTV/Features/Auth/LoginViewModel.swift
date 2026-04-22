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

    // Auth result stored for finalization after animation.
    // savedPassword is set only for regular (non-Quick-Connect) logins —
    // we cache it in the keychain so Seerr can reuse it without asking
    // the user to retype.
    var authResult: (server: JellyfinServer, user: JellyfinUser, token: String, savedPassword: String?)?

    let server: JellyfinServer

    private let authService: JellyfinAuthServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let dependencies: DependencyContainer
    private var quickConnectSecret: String?
    private var quickConnectTask: Task<Void, Never>?

    init(
        server: JellyfinServer,
        preSelectedUser: JellyfinUser? = nil,
        dependencies: DependencyContainer
    ) {
        self.server = server
        self.authService = dependencies.jellyfinAuthService
        self.keychainService = dependencies.keychainService
        self.dependencies = dependencies
        // Pre-fill the username when the caller already picked a user
        // from the `/Users/Public` list — avoids re-typing and leaves
        // the password field as the only thing left to touch.
        if let preSelectedUser {
            self.username = preSelectedUser.name
        }
        dependencies.jellyfinClient.baseURL = server.url
    }

    func login() async {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await authService.login(username: username, password: password)
            authResult = (server, response.user, response.accessToken, password)
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
            authResult = (server, response.user, response.accessToken, String?.none)
            isLoading = false
            loginSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func finalizeAuth() throws {
        guard let result = authResult else { return }
        try dependencies.saveSession(
            server: result.server,
            user: result.user,
            token: result.token,
            password: result.savedPassword
        )
    }
}
