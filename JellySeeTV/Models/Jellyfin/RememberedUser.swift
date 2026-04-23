import Foundation

/// A Jellyfin profile whose access token has been persisted so the
/// user can switch between it and other profiles without re-entering
/// credentials. One entry per (server, user) pair.
///
/// The token itself is a long-lived Jellyfin access token — tokens
/// only go invalid if the server admin revokes them. A 401 on switch
/// is therefore the signal to drop the entry and ask the user for
/// their password again for that specific profile.
struct RememberedUser: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let serverID: String
    let name: String
    let imageTag: String?
    let token: String
    let addedAt: Date

    init(
        id: String,
        serverID: String,
        name: String,
        imageTag: String?,
        token: String,
        addedAt: Date = .now
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.imageTag = imageTag
        self.token = token
        self.addedAt = addedAt
    }
}
