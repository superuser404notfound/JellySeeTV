import Foundation

enum KeychainKeys {
    static let service = "de.superuser404.JellySeeTV"

    static func accessToken(serverID: String) -> String {
        "accessToken_\(serverID)"
    }

    static func serverURL(serverID: String) -> String {
        "serverURL_\(serverID)"
    }

    static func userID(serverID: String) -> String {
        "userID_\(serverID)"
    }

    static func jellyfinPassword(serverID: String) -> String {
        "jellyfinPassword_\(serverID)"
    }

    /// JSON-encoded `[RememberedUser]` array for one server. All
    /// profile-switching state lives under this single blob so
    /// adds/removes are atomic writes.
    static func rememberedUsers(serverID: String) -> String {
        "rememberedUsers_\(serverID)"
    }

    static let seerrServer = "seerrServer"

    static func seerrSession(serverID: String) -> String {
        "seerrSession_\(serverID)"
    }

    /// JSON-encoded `RememberedSeerrSession` for a specific Jellyfin
    /// profile. Lets profile switching restore each user's own Seerr
    /// login instead of forcing them to re-auth on every swap.
    static func rememberedSeerr(jellyfinServerID: String, jellyfinUserID: String) -> String {
        "rememberedSeerr_\(jellyfinServerID)_\(jellyfinUserID)"
    }
}
