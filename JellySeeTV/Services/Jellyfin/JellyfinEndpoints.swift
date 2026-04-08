import Foundation

enum JellyfinEndpoint: APIEndpoint {
    // Server
    case publicInfo

    // Auth
    case authenticateByName(username: String, password: String)

    // Quick Connect
    case quickConnectInitiate
    case quickConnectCheck(secret: String)
    case quickConnectAuthenticate(secret: String)

    var path: String {
        switch self {
        case .publicInfo:
            "/System/Info/Public"
        case .authenticateByName:
            "/Users/AuthenticateByName"
        case .quickConnectInitiate:
            "/QuickConnect/Initiate"
        case .quickConnectCheck:
            "/QuickConnect/Connect"
        case .quickConnectAuthenticate:
            "/Users/AuthenticateWithQuickConnect"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .publicInfo, .quickConnectCheck:
            .get
        case .authenticateByName, .quickConnectInitiate, .quickConnectAuthenticate:
            .post
        }
    }

    var queryItems: [URLQueryItem]? {
        switch self {
        case .quickConnectCheck(let secret):
            [URLQueryItem(name: "secret", value: secret)]
        default:
            nil
        }
    }

    var body: (any Encodable & Sendable)? {
        switch self {
        case .authenticateByName(let username, let password):
            AuthenticateBody(username: username, pw: password)
        case .quickConnectAuthenticate(let secret):
            QuickConnectAuthBody(secret: secret)
        default:
            nil
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .publicInfo, .authenticateByName, .quickConnectInitiate, .quickConnectCheck:
            false
        case .quickConnectAuthenticate:
            true
        }
    }
}

private struct AuthenticateBody: Encodable, Sendable {
    let username: String
    let pw: String

    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case pw = "Pw"
    }
}

private struct QuickConnectAuthBody: Encodable, Sendable {
    let secret: String

    enum CodingKeys: String, CodingKey {
        case secret = "Secret"
    }
}
