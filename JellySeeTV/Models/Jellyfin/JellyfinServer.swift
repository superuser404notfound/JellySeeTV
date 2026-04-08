import Foundation

struct JellyfinServer: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    let version: String?

    init(id: String, name: String, url: URL, version: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.version = version
    }
}

struct JellyfinPublicServerInfo: Codable, Sendable {
    let id: String
    let serverName: String
    let version: String
    let startupWizardCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
        case version = "Version"
        case startupWizardCompleted = "StartupWizardCompleted"
    }
}
