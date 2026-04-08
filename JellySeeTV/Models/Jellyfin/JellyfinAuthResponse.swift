import Foundation

struct JellyfinAuthResponse: Codable, Sendable {
    let user: JellyfinUser
    let accessToken: String
    let serverID: String

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverID = "ServerId"
    }
}
