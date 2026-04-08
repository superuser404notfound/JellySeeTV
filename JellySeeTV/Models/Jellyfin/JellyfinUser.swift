import Foundation

struct JellyfinUser: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let serverID: String
    let hasPassword: Bool?
    let primaryImageTag: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case serverID = "ServerId"
        case hasPassword = "HasPassword"
        case primaryImageTag = "PrimaryImageTag"
    }
}
