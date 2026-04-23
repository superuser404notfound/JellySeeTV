import Foundation

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data?)
    case decodingError(Error)
    case networkError(Error)
    /// 401 from the server. `message` carries the server-provided
    /// reason (e.g. "Incorrect credentials", "Media server has not
    /// been set up yet") when the response body contained one, so
    /// the user sees a real explanation instead of a generic prompt.
    case unauthorized(message: String?)
    case serverUnreachable
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            String(localized: "error.invalidURL", defaultValue: "Invalid URL")
        case .invalidResponse:
            String(localized: "error.invalidResponse", defaultValue: "Invalid server response")
        case .httpError(let statusCode, _):
            String(localized: "error.httpError", defaultValue: "Server error (\(statusCode))")
        case .decodingError:
            String(localized: "error.decodingError", defaultValue: "Failed to process server response")
        case .networkError:
            String(localized: "error.networkError", defaultValue: "Network connection failed")
        case .unauthorized(let message):
            message ?? String(localized: "error.unauthorized", defaultValue: "Authentication required")
        case .serverUnreachable:
            String(localized: "error.serverUnreachable", defaultValue: "Server unreachable")
        case .timeout:
            String(localized: "error.timeout", defaultValue: "Request timed out")
        }
    }
}
