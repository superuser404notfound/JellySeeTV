import Foundation

protocol ServerDiscoveryServiceProtocol: Sendable {
    func discoverServer(input: String) async -> ServerDiscoveryResult
}

enum ServerDiscoveryResult: Sendable {
    case success(url: URL, serverInfo: ServerDiscoveryInfo)
    case failure(APIError)
}

struct ServerDiscoveryInfo: Sendable {
    let id: String
    let serverName: String
    let version: String
}

final class ServerDiscoveryService: ServerDiscoveryServiceProtocol {
    private let httpClient: HTTPClientProtocol

    nonisolated init(httpClient: HTTPClientProtocol = HTTPClient()) {
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
                let info = ServerDiscoveryInfo(
                    id: serverInfo.id,
                    serverName: serverInfo.serverName,
                    version: serverInfo.version
                )
                return .success(url: url, serverInfo: info)
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
