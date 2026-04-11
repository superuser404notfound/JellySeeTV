import Foundation

protocol JellyfinPlaybackServiceProtocol: Sendable {
    func getPlaybackInfo(itemID: String, userID: String, profile: [String: Any]?) async throws -> PlaybackInfoResponse
    func reportPlaybackStart(_ report: PlaybackStartReport) async throws
    func reportPlaybackProgress(_ report: PlaybackProgressReport) async throws
    func reportPlaybackStopped(_ report: PlaybackStopReport) async throws
    func buildStreamURL(itemID: String, mediaSourceID: String, container: String?, isStatic: Bool) -> URL?
    func buildTranscodeURL(relativePath: String) -> URL?
}

final class JellyfinPlaybackService: JellyfinPlaybackServiceProtocol {
    let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func getPlaybackInfo(itemID: String, userID: String, profile: [String: Any]? = nil) async throws -> PlaybackInfoResponse {
        guard let baseURL = client.baseURL else { throw APIError.invalidURL }

        var components = URLComponents(url: baseURL.appendingPathComponent("/Items/\(itemID)/PlaybackInfo"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "UserId", value: userID)]

        guard let url = components?.url else { throw APIError.invalidURL }

        // The caller (PlayerViewModel / DetailViewModel) is responsible
        // for picking the right profile, since DirectPlayProfile.current()
        // touches UIScreen and must run on the main actor. Fall back to
        // an empty profile only if no caller hands one in (shouldn't
        // happen in practice).
        let deviceProfile = profile ?? [:]
        let body: [String: Any] = ["DeviceProfile": deviceProfile]
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

    func buildStreamURL(itemID: String, mediaSourceID: String, container: String?, isStatic: Bool) -> URL? {
        guard let baseURL = client.baseURL else { return nil }
        let ext = container ?? "mp4"
        var components = URLComponents(url: baseURL.appendingPathComponent("/Videos/\(itemID)/stream.\(ext)"), resolvingAgainstBaseURL: true)
        var queryItems = [
            URLQueryItem(name: "MediaSourceId", value: mediaSourceID),
            URLQueryItem(name: "api_key", value: client.accessToken),
        ]
        if isStatic {
            queryItems.append(URLQueryItem(name: "Static", value: "true"))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    func buildTranscodeURL(relativePath: String) -> URL? {
        guard let baseURL = client.baseURL else { return nil }
        // Jellyfin returns TranscodingUrl as a path with query string, e.g.
        // "/videos/<id>/main.m3u8?DeviceId=...&MediaSourceId=...&api_key=..."
        // We need to splice that onto the base URL while keeping the query.
        // URL.appendingPathComponent would percent-encode the '?', so use
        // URLComponents directly.
        let trimmed = relativePath.hasPrefix("/") ? relativePath : "/\(relativePath)"
        guard let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        return url
    }
}
