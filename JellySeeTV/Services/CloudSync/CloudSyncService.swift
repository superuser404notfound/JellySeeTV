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

/// Uses UserDefaults as local storage. iCloud sync can be added later
/// when the ubiquity-kvstore-identifier entitlement is configured.
/// NSUbiquitousKeyValueStore.default crashes (SIGABRT) without it.
final class CloudSyncService: CloudSyncServiceProtocol {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let serverList = "syncedServerList"
        static let preferences = "syncedPreferences"
    }

    func saveServerList(_ servers: [JellyfinServer]) {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        defaults.set(data, forKey: Keys.serverList)
    }

    func loadServerList() -> [JellyfinServer] {
        guard let data = defaults.data(forKey: Keys.serverList),
              let servers = try? JSONDecoder().decode([JellyfinServer].self, from: data)
        else {
            return []
        }
        return servers
    }

    func savePreferences(_ preferences: SyncablePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Keys.preferences)
    }

    func loadPreferences() -> SyncablePreferences? {
        guard let data = defaults.data(forKey: Keys.preferences) else { return nil }
        return try? JSONDecoder().decode(SyncablePreferences.self, from: data)
    }

    func synchronize() {
        // UserDefaults syncs automatically
    }
}
