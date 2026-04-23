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
}
