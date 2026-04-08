import Foundation

@MainActor
final class JellyfinClient {
    let httpClient: HTTPClientProtocol
    private let deviceID: String
    private let appVersion: String

    var baseURL: URL?
    var accessToken: String?

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
        self.deviceID = Self.getOrCreateDeviceID()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func request<T: Decodable & Sendable>(
        endpoint: APIEndpoint,
        responseType: T.Type
    ) async throws -> T {
        guard let baseURL else { throw APIError.invalidURL }
        let headers = buildHeaders(requiresAuth: endpoint.requiresAuth)
        return try await httpClient.request(
            baseURL: baseURL,
            endpoint: endpoint,
            headers: headers,
            responseType: responseType
        )
    }

    func request(endpoint: APIEndpoint) async throws {
        guard let baseURL else { throw APIError.invalidURL }
        let headers = buildHeaders(requiresAuth: endpoint.requiresAuth)
        try await httpClient.request(
            baseURL: baseURL,
            endpoint: endpoint,
            headers: headers
        )
    }

    private func buildHeaders(requiresAuth: Bool) -> [String: String] {
        var headers: [String: String] = [:]

        var authParts = [
            "Client=\"JellySeeTV\"",
            "Device=\"Apple TV\"",
            "DeviceId=\"\(deviceID)\"",
            "Version=\"\(appVersion)\"",
        ]

        if requiresAuth, let token = accessToken {
            authParts.append("Token=\"\(token)\"")
        }

        headers["Authorization"] = "MediaBrowser \(authParts.joined(separator: ", "))"
        headers["Accept"] = "application/json"

        return headers
    }

    private static func getOrCreateDeviceID() -> String {
        let key = "JellySeeTV_DeviceID"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }
}
