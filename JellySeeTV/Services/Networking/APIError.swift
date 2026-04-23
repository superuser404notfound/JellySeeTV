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
        case .httpError(let statusCode, let data):
            if let message = Self.extractErrorMessage(from: data) {
                String(
                    localized: "error.httpError.withMessage",
                    defaultValue: "HTTP \(statusCode) · \(message)"
                )
            } else {
                String(localized: "error.httpError", defaultValue: "Server error (\(statusCode))")
            }
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

    /// Best-effort decode of a Jellyfin/Jellyseerr JSON error body —
    /// surfaces the server's real reason ("Invalid password",
    /// "Media server has not been set up yet", …) instead of the
    /// generic HTTP-code fallback. Falls back to a truncated raw
    /// body when the response isn't JSON with a message/error field.
    static func extractErrorMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = (json["message"] as? String) ?? (json["error"] as? String),
           !message.isEmpty {
            return message
        }
        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(200))
    }
}
