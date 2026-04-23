import Foundation

protocol SeerrAuthServiceProtocol: Sendable {
    func loginWithJellyfin(username: String, password: String) async throws -> SeerrUser
    func currentUser() async throws -> SeerrUser
    func logout() async throws
}

@MainActor
final class SeerrAuthService: SeerrAuthServiceProtocol {
    private let client: SeerrClient

    init(client: SeerrClient) {
        self.client = client
    }

    func loginWithJellyfin(username: String, password: String) async throws -> SeerrUser {
        // Drop any residual cookie before the login POST. The client
        // otherwise attaches the old connect.sid on every request, and
        // a stale/invalid cookie can make Seerr reject the fresh
        // credentials with 401 before it looks at the body.
        client.sessionCookie = nil

        let body = SeerrJellyfinAuthBody(username: username, password: password)
        let (user, response) = try await client.requestWithResponse(
            endpoint: SeerrEndpoint.authJellyfin(body: body),
            responseType: SeerrUser.self
        )
        guard let cookie = client.extractSessionCookie(from: response) else {
            throw APIError.unauthorized(message: nil)
        }
        client.sessionCookie = cookie
        return user
    }

    func currentUser() async throws -> SeerrUser {
        try await client.request(
            endpoint: SeerrEndpoint.authMe,
            responseType: SeerrUser.self
        )
    }

    func logout() async throws {
        try await client.request(endpoint: SeerrEndpoint.authLogout)
        client.sessionCookie = nil
    }
}
