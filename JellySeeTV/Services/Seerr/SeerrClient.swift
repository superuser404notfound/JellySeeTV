import Foundation

@MainActor
final class SeerrClient {
    let httpClient: HTTPClientProtocol

    var baseURL: URL?
    var sessionCookie: String?

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(httpClient: HTTPClientProtocol = HTTPClient()) {
        self.httpClient = httpClient

        // Seerr returns TMDB-shaped JSON with snake_case keys (poster_path,
        // first_air_date, vote_average, …) so we convert on decode — but
        // POST bodies are camelCase (useSsl, urlBase, mediaId, mediaType)
        // and the API rejects snake_case there with HTTP 500.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        self.encoder = JSONEncoder()
    }

    func request<T: Decodable>(
        endpoint: APIEndpoint,
        responseType: T.Type
    ) async throws -> T {
        guard let baseURL else { throw APIError.invalidURL }
        let headers = buildHeaders()
        let (data, _) = try await httpClient.requestData(
            baseURL: baseURL,
            endpoint: endpoint,
            headers: headers
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func request(endpoint: APIEndpoint) async throws {
        guard let baseURL else { throw APIError.invalidURL }
        let headers = buildHeaders()
        _ = try await httpClient.requestData(
            baseURL: baseURL,
            endpoint: endpoint,
            headers: headers
        )
    }

    func requestWithResponse<T: Decodable>(
        endpoint: APIEndpoint,
        responseType: T.Type
    ) async throws -> (T, HTTPURLResponse) {
        guard let baseURL else { throw APIError.invalidURL }
        let headers = buildHeaders()
        let (data, response) = try await httpClient.requestData(
            baseURL: baseURL,
            endpoint: endpoint,
            headers: headers
        )
        do {
            let value = try decoder.decode(T.self, from: data)
            return (value, response)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func buildHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        headers["Accept"] = "application/json"
        if let sessionCookie {
            headers["Cookie"] = sessionCookie
        }
        return headers
    }

    func extractSessionCookie(from response: HTTPURLResponse) -> String? {
        guard let baseURL,
              let headerFields = response.allHeaderFields as? [String: String]
        else { return nil }

        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: baseURL)
        guard let sessionCookie = cookies.first(where: { $0.name == "connect.sid" }) else {
            return nil
        }
        return "\(sessionCookie.name)=\(sessionCookie.value)"
    }
}
