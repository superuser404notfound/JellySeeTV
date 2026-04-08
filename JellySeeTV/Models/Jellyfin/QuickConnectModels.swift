import Foundation

struct QuickConnectInitResponse: Codable, Sendable {
    let secret: String
    let code: String
    let authenticated: Bool

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
        case code = "Code"
        case authenticated = "Authenticated"
    }
}

struct QuickConnectCheckResponse: Codable, Sendable {
    let authenticated: Bool

    enum CodingKeys: String, CodingKey {
        case authenticated = "Authenticated"
    }
}
