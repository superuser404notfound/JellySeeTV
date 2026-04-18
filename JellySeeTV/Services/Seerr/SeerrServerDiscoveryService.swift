import Foundation

struct SeerrServerInfo: Codable, Sendable {
    let version: String
    let commitTag: String?
}

enum SeerrServerDiscoveryResult: Sendable {
    case success(url: URL, info: SeerrServerInfo)
    case failure(APIError)
}

protocol SeerrServerDiscoveryServiceProtocol: Sendable {
    func discoverServer(input: String) async -> SeerrServerDiscoveryResult
}

final class SeerrServerDiscoveryService: SeerrServerDiscoveryServiceProtocol {
    private let httpClient: HTTPClientProtocol
    private let decoder: JSONDecoder

    nonisolated init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func discoverServer(input: String) async -> SeerrServerDiscoveryResult {
        let candidates = buildCandidateURLs(from: input)

        for url in candidates {
            do {
                let (data, _) = try await httpClient.requestData(
                    baseURL: url,
                    endpoint: SeerrEndpoint.status,
                    headers: ["Accept": "application/json"]
                )
                let info = try decoder.decode(SeerrServerInfo.self, from: data)
                return .success(url: url, info: info)
            } catch {
                continue
            }
        }

        return .failure(.serverUnreachable)
    }

    private func buildCandidateURLs(from input: String) -> [URL] {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if cleaned.hasPrefix("https://") || cleaned.hasPrefix("http://") {
            guard let url = URL(string: cleaned) else { return [] }
            var candidates = [url]
            if url.port == nil {
                if cleaned.hasPrefix("http://"), let withPort = URL(string: "\(cleaned):5055") {
                    candidates.append(withPort)
                }
            }
            return candidates
        }

        let isIPAddress = cleaned.range(
            of: #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"#,
            options: .regularExpression
        ) != nil
        let hasPort = cleaned.contains(":")

        var candidates: [URL] = []

        if isIPAddress {
            if hasPort {
                if let https = URL(string: "https://\(cleaned)") { candidates.append(https) }
                if let http = URL(string: "http://\(cleaned)") { candidates.append(http) }
            } else {
                if let url = URL(string: "http://\(cleaned):5055") { candidates.append(url) }
                if let url = URL(string: "https://\(cleaned):5055") { candidates.append(url) }
                if let url = URL(string: "https://\(cleaned)") { candidates.append(url) }
                if let url = URL(string: "http://\(cleaned)") { candidates.append(url) }
            }
        } else {
            if let url = URL(string: "https://\(cleaned)") { candidates.append(url) }
            if let url = URL(string: "http://\(cleaned)") { candidates.append(url) }
            if let url = URL(string: "http://\(cleaned):5055") { candidates.append(url) }
            if let url = URL(string: "https://\(cleaned):5055") { candidates.append(url) }
        }

        return candidates
    }
}
