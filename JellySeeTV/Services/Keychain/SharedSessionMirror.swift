import Foundation
import os.log
import Security

/// Writes the active Jellyfin credentials into the shared keychain
/// access group that the TopShelf extension reads from. Three keys
/// per session: server URL, user ID, access token. Re-mirrored on
/// every login, profile switch, and logout to keep the extension's
/// view in lockstep with the running app.
///
/// Lives in its own service bucket (`…JellySeeTV.shared`) so the
/// main app's primary keychain entries (in the default access
/// group) stay logically separated from the shelf's narrow
/// projection — even though both physically share the same
/// app-bundle keychain unless the .shared access group resolves at
/// runtime, in which case the mirror lands in that group.
enum SharedSessionMirror {
    static let service = "de.superuser404.JellySeeTV.shared"

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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if let group = resolvedAccessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("SharedSessionMirror.save failed: status=\(status, privacy: .public) account=\(account, privacy: .public)")
        }
    }

    private static func delete(account: String) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group = resolvedAccessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        SecItemDelete(query as CFDictionary)
    }

    /// Materializes the actual `<TeamID>.de.superuser404.JellySeeTV.shared`
    /// string at runtime — `$(AppIdentifierPrefix)` only expands at
    /// codesign, never at `SecItemAdd`. We crib the team prefix off
    /// any keychain item the process can already see (the main
    /// app's KeychainService has always written at least `activeServer`
    /// by the time the mirror runs). When no items exist yet (truly
    /// fresh install, somehow called pre-login), we drop the access
    /// group from the query and let the OS fall back to the first
    /// entitled group — losing some isolation but keeping the write
    /// from failing outright.
    private static let resolvedAccessGroup: String? = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(probe as CFDictionary, &item)
        guard status == errSecSuccess,
              let attrs = item as? [String: Any],
              let group = attrs[kSecAttrAccessGroup as String] as? String,
              let dot = group.firstIndex(of: ".")
        else {
            log.notice("SharedSessionMirror could not probe team prefix; falling back to default group")
            return nil
        }
        let prefix = String(group[..<group.index(after: dot)])
        return prefix + "de.superuser404.JellySeeTV.shared"
    }()

    private static let log = Logger(subsystem: "de.superuser404.JellySeeTV", category: "TopShelfMirror")
}
