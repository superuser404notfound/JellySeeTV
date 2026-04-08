import Foundation

protocol ServerDiscoveryServiceProtocol: Sendable {
    func discoverServer(input: String) async -> ServerDiscoveryResult
}

enum ServerDiscoveryResult: Sendable {
    case success(url: URL, serverInfo: JellyfinPublicServerInfo)
    case failure(APIError)
}

final class ServerDiscoveryService: ServerDiscoveryServiceProtocol {
    private let httpClient: HTTPClientProtocol

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
    }

    func discoverServer(input: String) async -> ServerDiscoveryResult {
        let candidates = buildCandidateURLs(from: input)

        for url in candidates {
            do {
                let serverInfo = try await httpClient.request(
                    baseURL: url,
                    endpoint: JellyfinEndpoint.publicInfo,
                    headers: ["Accept": "application/json"],
                    responseType: JellyfinPublicServerInfo.self
                )
                return .success(url: url, serverInfo: serverInfo)
            } catch {
                continue
            }
        }

        return .failure(.serverUnreachable)
    }

    private func buildCandidateURLs(from input: String) -> [URL] {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // If already a full URL, try it directly
        if cleaned.hasPrefix("https://") || cleaned.hasPrefix("http://") {
            if let url = URL(string: cleaned) {
                return [url]
            }
            return []
        }

        // Try https first, then http
        var candidates: [URL] = []
        if let https = URL(string: "https://\(cleaned)") {
            candidates.append(https)
        }
        if let http = URL(string: "http://\(cleaned)") {
            candidates.append(http)
        }

        return candidates
    }
}
