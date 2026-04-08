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

        // If already a full URL with scheme, try it directly + with default ports
        if cleaned.hasPrefix("https://") || cleaned.hasPrefix("http://") {
            if let url = URL(string: cleaned) {
                // If no port specified, also try with default Jellyfin ports
                var candidates = [url]
                if url.port == nil {
                    if cleaned.hasPrefix("https://"), let withPort = URL(string: "\(cleaned):8920") {
                        candidates.append(withPort)
                    }
                    if cleaned.hasPrefix("http://"), let withPort = URL(string: "\(cleaned):8096") {
                        candidates.append(withPort)
                    }
                }
                return candidates
            }
            return []
        }

        let isIPAddress = cleaned.range(of: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"#, options: .regularExpression) != nil
        let hasPort = cleaned.contains(":")

        var candidates: [URL] = []

        if isIPAddress {
            if hasPort {
                // IP with explicit port: try both schemes
                if let https = URL(string: "https://\(cleaned)") { candidates.append(https) }
                if let http = URL(string: "http://\(cleaned)") { candidates.append(http) }
            } else {
                // IP without port: try default Jellyfin ports
                // HTTPS with Jellyfin HTTPS port
                if let url = URL(string: "https://\(cleaned):8920") { candidates.append(url) }
                // HTTP with Jellyfin HTTP port
                if let url = URL(string: "http://\(cleaned):8096") { candidates.append(url) }
                // Also try standard ports (reverse proxy setup)
                if let url = URL(string: "https://\(cleaned)") { candidates.append(url) }
                if let url = URL(string: "http://\(cleaned)") { candidates.append(url) }
            }
        } else {
            // Domain name: try standard ports first (likely reverse proxy), then Jellyfin ports
            if let url = URL(string: "https://\(cleaned)") { candidates.append(url) }
            if let url = URL(string: "http://\(cleaned)") { candidates.append(url) }
            if let url = URL(string: "https://\(cleaned):8920") { candidates.append(url) }
            if let url = URL(string: "http://\(cleaned):8096") { candidates.append(url) }
        }

        return candidates
    }
}
