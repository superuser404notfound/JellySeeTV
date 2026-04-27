import Foundation
import Security

/// Writes the active Jellyfin credentials into the shared keychain
/// access group that the TopShelf extension reads from. Three keys
/// per session: server URL, user ID, access token. Re-mirrored on
/// every login, profile switch, and logout to keep the extension's
/// view in lockstep with the running app.
///
/// Lives in its own service bucket (`…JellySeeTV.shared`) and its
/// own access group so the main app's primary keychain stays
/// untouched — the mirror is a deliberate, narrow projection of
/// only what the shelf needs.
enum SharedSessionMirror {
    static let service = "de.superuser404.JellySeeTV.shared"
    static let accessGroup = "$(AppIdentifierPrefix)de.superuser404.JellySeeTV.shared"

    static let serverURLKey = "shared.serverURL"
    static let userIDKey = "shared.userID"
    static let accessTokenKey = "shared.accessToken"

    static func write(serverURL: URL, userID: String, accessToken: String) {
        save(serverURL.absoluteString, account: serverURLKey)
        save(userID, account: userIDKey)
        save(accessToken, account: accessTokenKey)
    }

    static func clear() {
        delete(account: serverURLKey)
        delete(account: userIDKey)
        delete(account: accessTokenKey)
    }

    private static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
