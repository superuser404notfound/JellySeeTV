import Foundation
import Security

/// Pulls the active Jellyfin session out of the shared keychain
/// access group that the main app mirrors credentials into. Read
/// only — the extension never writes here.
///
/// The main app remains the single source of truth for auth state;
/// every login/switch/logout writes through `SharedSessionMirror`
/// which keeps these three keys in sync. If any one of them is
/// missing we treat the session as absent and the TopShelf renders
/// empty rather than guessing.
struct SharedSession: Sendable {
    let baseURL: URL
    let userID: String
    let accessToken: String

    static func load() -> SharedSession? {
        guard let urlString = readSharedKeychainString(account: SharedSessionKeys.serverURL),
              let url = URL(string: urlString),
              let userID = readSharedKeychainString(account: SharedSessionKeys.userID),
              let token = readSharedKeychainString(account: SharedSessionKeys.accessToken)
        else {
            return nil
        }
        return SharedSession(baseURL: url, userID: userID, accessToken: token)
    }
}

enum SharedSessionKeys {
    static let service = "de.superuser404.JellySeeTV.shared"
    static let accessGroup = "$(AppIdentifierPrefix)de.superuser404.JellySeeTV.shared"

    static let serverURL = "shared.serverURL"
    static let userID = "shared.userID"
    static let accessToken = "shared.accessToken"
}

private func readSharedKeychainString(account: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: SharedSessionKeys.service,
        kSecAttrAccount as String: account,
        kSecAttrAccessGroup as String: resolvedAccessGroup,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

/// `$(AppIdentifierPrefix)` only expands inside entitlement plists —
/// at runtime the prefix is the team ID followed by a dot, recovered
/// here by querying any one keychain item the process can already
/// see and reading its `kSecAttrAccessGroup` back. Falls back to the
/// raw entitlement value as a last resort so a brand-new install
/// (with nothing in the keychain yet) still finds its bucket on the
/// next read.
private let resolvedAccessGroup: String = {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnAttributes as String: true,
    ]
    var item: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecSuccess,
       let attrs = item as? [String: Any],
       let group = attrs[kSecAttrAccessGroup as String] as? String,
       let dot = group.firstIndex(of: ".") {
        let prefix = String(group[..<group.index(after: dot)])
        return prefix + "de.superuser404.JellySeeTV.shared"
    }
    return SharedSessionKeys.accessGroup
}()
