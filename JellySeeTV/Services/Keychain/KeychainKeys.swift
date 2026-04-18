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

    static let seerrServer = "seerrServer"

    static func seerrSession(serverID: String) -> String {
        "seerrSession_\(serverID)"
    }
}
