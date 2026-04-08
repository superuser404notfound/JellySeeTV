import Foundation

struct QuickConnectInitResponse: Codable, Sendable {
    let secret: String
    let code: String
    let isAuthorized: Bool

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
        case code = "Code"
        case isAuthorized = "IsAuthorized"
    }
}

struct QuickConnectCheckResponse: Codable, Sendable {
    let isAuthorized: Bool

    enum CodingKeys: String, CodingKey {
        case isAuthorized = "IsAuthorized"
    }
}
