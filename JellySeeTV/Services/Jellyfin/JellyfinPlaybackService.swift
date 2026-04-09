import Foundation

protocol JellyfinPlaybackServiceProtocol: Sendable {
    func getPlaybackInfo(itemID: String, userID: String) async throws -> PlaybackInfoResponse
    func reportPlaybackStart(_ report: PlaybackStartReport) async throws
    func reportPlaybackProgress(_ report: PlaybackProgressReport) async throws
    func reportPlaybackStopped(_ report: PlaybackStopReport) async throws
    func buildStreamURL(itemID: String, mediaSourceID: String, isDirectStream: Bool) -> URL?
    func buildTranscodeURL(relativePath: String) -> URL?
}

final class JellyfinPlaybackService: JellyfinPlaybackServiceProtocol {
    let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func getPlaybackInfo(itemID: String, userID: String) async throws -> PlaybackInfoResponse {
        guard let baseURL = client.baseURL else { throw APIError.invalidURL }

        // Build URL manually to include UserId query param
        var components = URLComponents(url: baseURL.appendingPathComponent("/Items/\(itemID)/PlaybackInfo"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "UserId", value: userID)]

        guard let url = components?.url else { throw APIError.invalidURL }

        // Build body with DeviceProfile as raw JSON
        let body: [String: Any] = ["DeviceProfile": DirectPlayProfile.build()]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add Jellyfin auth header
        let authHeader = client.buildAuthHeader()
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            #if DEBUG
            print("[PlaybackInfo] Status: \(httpResponse.statusCode)")
            print("[PlaybackInfo] URL: \(url)")
            if let bodyStr = String(data: bodyData, encoding: .utf8) {
                print("[PlaybackInfo] Body: \(bodyStr.prefix(500))")
            }
            if let respStr = String(data: data, encoding: .utf8) {
                print("[PlaybackInfo] Response: \(respStr.prefix(500))")
            }
            #endif
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(PlaybackInfoResponse.self, from: data)
    }

    func reportPlaybackStart(_ report: PlaybackStartReport) async throws {
        try await client.request(
            endpoint: JellyfinEndpoint.sessionPlaying(report: report)
        )
    }

    func reportPlaybackProgress(_ report: PlaybackProgressReport) async throws {
        try await client.request(
            endpoint: JellyfinEndpoint.sessionProgress(report: report)
        )
    }

    func reportPlaybackStopped(_ report: PlaybackStopReport) async throws {
        try await client.request(
            endpoint: JellyfinEndpoint.sessionStopped(report: report)
        )
    }

    func buildStreamURL(itemID: String, mediaSourceID: String, isDirectStream: Bool) -> URL? {
        guard let baseURL = client.baseURL else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("/Videos/\(itemID)/stream"), resolvingAgainstBaseURL: true)
        var queryItems = [
            URLQueryItem(name: "MediaSourceId", value: mediaSourceID),
            URLQueryItem(name: "api_key", value: client.accessToken),
        ]
        if isDirectStream {
            queryItems.append(URLQueryItem(name: "Static", value: "true"))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    func buildTranscodeURL(relativePath: String) -> URL? {
        guard let baseURL = client.baseURL else { return nil }
        return URL(string: "\(baseURL)\(relativePath)")
    }
}
