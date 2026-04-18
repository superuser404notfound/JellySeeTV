import Foundation

protocol JellyfinPlaybackServiceProtocol: Sendable {
    var baseURL: URL? { get }
    func getPlaybackInfo(itemID: String, userID: String, profile: [String: Any]?) async throws -> PlaybackInfoResponse
    func reportPlaybackStart(_ report: PlaybackStartReport) async throws
    func reportPlaybackProgress(_ report: PlaybackProgressReport) async throws
    func reportPlaybackStopped(_ report: PlaybackStopReport) async throws
    func getNextEpisode(seriesID: String, userID: String) async throws -> JellyfinItem?
    func getEpisodes(seriesID: String, seasonID: String, userID: String) async throws -> [JellyfinItem]
    func getIntroSegment(itemID: String) async throws -> MediaSegment?
    func buildStreamURL(itemID: String, mediaSourceID: String, container: String?, isStatic: Bool) -> URL?
    func buildSubtitleURL(itemID: String, mediaSourceID: String, streamIndex: Int, format: String) -> URL?
    func buildTranscodeURL(relativePath: String) -> URL?
}

final class JellyfinPlaybackService: JellyfinPlaybackServiceProtocol {
    let client: JellyfinClient

    var baseURL: URL? { client.baseURL }

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

        #if DEBUG
        if let dp = (deviceProfile["DirectPlayProfiles"] as? [[String: Any]])?.first {
            print("[PlaybackInfo] DirectPlay containers: \(dp["Container"] ?? "none")")
        }
        #endif

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

        #if DEBUG
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sources = json["MediaSources"] as? [[String: Any]],
           let first = sources.first {
            print("[PlaybackInfo] Response container=\(first["Container"] ?? "nil"), directPlay=\(first["SupportsDirectPlay"] ?? "nil"), directStream=\(first["SupportsDirectStream"] ?? "nil")")
            if let reason = first["TranscodingUrl"] as? String, reason.contains("TranscodeReasons") {
                if let range = reason.range(of: "TranscodeReasons=") {
                    let reasons = reason[range.upperBound...]
                    print("[PlaybackInfo] TranscodeReasons: \(reasons.prefix(100))")
                }
            }
        }
        #endif

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

    func getNextEpisode(seriesID: String, userID: String) async throws -> JellyfinItem? {
        let response: JellyfinItemsResponse = try await client.request(
            endpoint: JellyfinEndpoint.nextUp(userID: userID, seriesID: seriesID, limit: 1),
            responseType: JellyfinItemsResponse.self
        )
        return response.items.first
    }

    func getEpisodes(seriesID: String, seasonID: String, userID: String) async throws -> [JellyfinItem] {
        let response: JellyfinItemsResponse = try await client.request(
            endpoint: JellyfinEndpoint.episodes(seriesID: seriesID, seasonID: seasonID, userID: userID),
            responseType: JellyfinItemsResponse.self
        )
        return response.items
    }

    /// Ask the server for intro markers on an item. Returns nil if the
    /// server doesn't expose the endpoint (Jellyfin pre-10.10 without
    /// the intro-skipper plugin → 404), or if no intro was detected.
    func getIntroSegment(itemID: String) async throws -> MediaSegment? {
        do {
            let response: MediaSegmentsResponse = try await client.request(
                endpoint: JellyfinEndpoint.mediaSegments(itemID: itemID),
                responseType: MediaSegmentsResponse.self
            )
            return response.items.first(where: { $0.type == .intro })
        } catch APIError.httpError(let status, _) where status == 404 {
            // Server doesn't expose MediaSegments — feature just stays off.
            return nil
        }
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

    func buildSubtitleURL(itemID: String, mediaSourceID: String, streamIndex: Int, format: String) -> URL? {
        guard let baseURL = client.baseURL else { return nil }
        let fmt = (format == "subrip") ? "srt" : format
        let path = "/Videos/\(itemID)/\(mediaSourceID)/Subtitles/\(streamIndex)/0/Stream.\(fmt)"
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "api_key", value: client.accessToken)]
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
