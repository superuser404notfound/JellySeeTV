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
        try await client.request(
            endpoint: JellyfinEndpoint.playbackInfo(itemID: itemID, userID: userID),
            responseType: PlaybackInfoResponse.self
        )
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
