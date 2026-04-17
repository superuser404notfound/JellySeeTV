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

final class CloudSyncService: CloudSyncServiceProtocol {
    /// Lazy — NSUbiquitousKeyValueStore.default crashes (SIGABRT) if the
    /// iCloud KVS entitlement is missing. Nil means iCloud sync unavailable.
    private lazy var store: NSUbiquitousKeyValueStore? = {
        // Guard: only access if the entitlement exists
        let store = NSUbiquitousKeyValueStore.default
        // Test access — if entitlement is missing, this returns empty but doesn't crash
        _ = store.dictionaryRepresentation
        return store
    }()

    private var isAvailable: Bool { store != nil }

    private enum Keys {
        static let serverList = "syncedServerList"
        static let preferences = "syncedPreferences"
    }

    func saveServerList(_ servers: [JellyfinServer]) {
        guard let store, let data = try? JSONEncoder().encode(servers) else { return }
        store.set(data, forKey: Keys.serverList)
        synchronize()
    }

    func loadServerList() -> [JellyfinServer] {
        guard let store,
              let data = store.data(forKey: Keys.serverList),
              let servers = try? JSONDecoder().decode([JellyfinServer].self, from: data)
        else {
            return []
        }
        return servers
    }

    func savePreferences(_ preferences: SyncablePreferences) {
        guard let store, let data = try? JSONEncoder().encode(preferences) else { return }
        store.set(data, forKey: Keys.preferences)
        synchronize()
    }

    func loadPreferences() -> SyncablePreferences? {
        guard let store, let data = store.data(forKey: Keys.preferences) else { return nil }
        return try? JSONDecoder().decode(SyncablePreferences.self, from: data)
    }

    func synchronize() {
        store?.synchronize()
    }
}
