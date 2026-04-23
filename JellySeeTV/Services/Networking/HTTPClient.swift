import Foundation

protocol HTTPClientProtocol: Sendable {
    func request<T: Decodable>(
        baseURL: URL,
        endpoint: APIEndpoint,
        headers: [String: String],
        responseType: T.Type
    ) async throws -> T

    func request(
        baseURL: URL,
        endpoint: APIEndpoint,
        headers: [String: String]
    ) async throws

    func requestData(
        baseURL: URL,
        endpoint: APIEndpoint,
        headers: [String: String]
    ) async throws -> (Data, HTTPURLResponse)
}

final class HTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated init(session: URLSession = .shared) {
        self.session = session

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func request<T: Decodable>(
        baseURL: URL,
        endpoint: APIEndpoint,
        headers: [String: String],
        responseType: T.Type
    ) async throws -> T {
        let (data, _) = try await requestData(baseURL: baseURL, endpoint: endpoint, headers: headers)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func request(
        baseURL: URL,
        endpoint: APIEndpoint,
        headers: [String: String]
    ) async throws {
        let _ = try await requestData(baseURL: baseURL, endpoint: endpoint, headers: headers)
    }

    func requestData(
        baseURL: URL,
        endpoint: APIEndpoint,
        headers: [String: String]
    ) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = try buildRequest(baseURL: baseURL, endpoint: endpoint, headers: headers)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut {
            throw APIError.timeout
        } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .cannotConnectToHost {
            throw APIError.serverUnreachable
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return (data, httpResponse)
        case 401:
            throw APIError.unauthorized(message: APIError.extractErrorMessage(from: data))
        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func buildRequest(
        baseURL: URL,
        endpoint: APIEndpoint,
        headers: [String: String]
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true)
        components?.queryItems = endpoint.queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = 30

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return request
    }
}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        _encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
