import Foundation

protocol JellyfinAuthServiceProtocol: Sendable {
    @MainActor func login(username: String, password: String) async throws -> JellyfinAuthResponse
    @MainActor func initiateQuickConnect() async throws -> QuickConnectInitResponse
    @MainActor func checkQuickConnect(secret: String) async throws -> Bool
    @MainActor func authenticateWithQuickConnect(secret: String) async throws -> JellyfinAuthResponse
}

@MainActor
final class JellyfinAuthService: JellyfinAuthServiceProtocol {
    private let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func login(username: String, password: String) async throws -> JellyfinAuthResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.authenticateByName(username: username, password: password),
            responseType: JellyfinAuthResponse.self
        )
    }

    func initiateQuickConnect() async throws -> QuickConnectInitResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.quickConnectInitiate,
            responseType: QuickConnectInitResponse.self
        )
    }

    func checkQuickConnect(secret: String) async throws -> Bool {
        let response = try await client.request(
            endpoint: JellyfinEndpoint.quickConnectCheck(secret: secret),
            responseType: QuickConnectCheckResponse.self
        )
        return response.isAuthorized
    }

    func authenticateWithQuickConnect(secret: String) async throws -> JellyfinAuthResponse {
        try await client.request(
            endpoint: JellyfinEndpoint.quickConnectAuthenticate(secret: secret),
            responseType: JellyfinAuthResponse.self
        )
    }
}
