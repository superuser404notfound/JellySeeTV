import Foundation

protocol CloudSyncServiceProtocol: Sendable {
    func saveServerList(_ servers: [JellyfinServer])
    func loadServerList() -> [JellyfinServer]
    func savePreferences(_ preferences: SyncablePreferences)
    func loadPreferences() -> SyncablePreferences?
    func synchronize()
}

struct SyncablePreferences: Codable, Sendable {
    var preferredAudioLanguage: String?
    var preferredSubtitleLanguage: String?
    var maxStreamingBitrate: Int?
}

/// Local storage for synced preferences and server list.
/// tvOS doesn't support iCloud KVS provisioning — UserDefaults
/// provides the same API without the entitlement requirement.
/// Data persists across app launches on the same device.
final class CloudSyncService: CloudSyncServiceProtocol {
    private let store = UserDefaults.standard

    private enum Keys {
        static let serverList = "syncedServerList"
        static let preferences = "syncedPreferences"
    }

    func saveServerList(_ servers: [JellyfinServer]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        store.set(data, forKey: Keys.serverList)
        synchronize()
    }

    func loadServerList() -> [JellyfinServer] {
        guard let data = store.data(forKey: Keys.serverList),
              let servers = try? JSONDecoder().decode([JellyfinServer].self, from: data)
        else {
            return []
        }
        return servers
    }

    func savePreferences(_ preferences: SyncablePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        store.set(data, forKey: Keys.preferences)
        synchronize()
    }

    func loadPreferences() -> SyncablePreferences? {
        guard let data = store.data(forKey: Keys.preferences) else { return nil }
        return try? JSONDecoder().decode(SyncablePreferences.self, from: data)
    }

    func synchronize() {
        store.synchronize()
    }
}
