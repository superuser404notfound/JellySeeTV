import Foundation

/// Persistent cache for the result sets behind the home + catalog
/// filter tiles (streaming providers, genres, studios). Three slices:
///
/// - **homeFilterItems**: the resolved JellyfinItem list for a Home
///   smart-filter tile (e.g. tap on Disney+). Cached as full
///   `JellyfinItem` blobs so a re-tap can render the grid the moment
///   the view appears, before any network roundtrip.
///
/// - **smartFilterIDs**: TMDB id list for a Home provider tile —
///   kept around even when the items themselves are cached, so a
///   downstream module that wants just the ids (e.g. for counting)
///   doesn't have to walk the full item array.
///
/// - **catalogPage**: the first page of items for a Catalog filter
///   tile. Pagination beyond page 1 still hits the network on
///   demand.
///
/// Stale-while-revalidate is intentional. Each refresh fully replaces
/// the cached value, so anything that left the provider's lineup
/// since last visit drops out automatically.
///
/// Backed by per-key JSON files in `Library/Caches/FilterCache/`.
/// Originally lived in `UserDefaults`, but tvOS enforces a 1 MB hard
/// cap per app domain on `CFPreferences` writes — and a fully
/// populated provider tile (50+ JellyfinItem blobs with overview,
/// image tags, media streams, …) routinely exceeds that, which
/// crashes the app with SIGABRT inside `defaults.set` on the very
/// first cache write. Files have no such cap and live in the same
/// directory iOS/tvOS uses for app caches, so the system can evict
/// them under disk pressure without us doing anything.
///
/// Thread safety: filesystem reads + writes are atomic at the OS
/// level, and we only read/write whole files. `@unchecked Sendable`
/// is therefore safe — there's no shared mutable state in the type
/// itself, just the directory pointer. Synchronous API throughout
/// so SwiftUI views can hit the cache from inside `init()` and have
/// the cached value populate `@State` in the same render pass.
final class FilterCache: @unchecked Sendable {
    static let shared = FilterCache()

    private let directory: URL
    private static let homeItemsPrefix = "homeItems."
    private static let smartIDPrefix = "smart."
    private static let catalogPrefix = "catalog."

    private struct HomeItemsEntry: Codable {
        let items: [JellyfinItem]
        let lastFetched: Date
    }

    private struct SmartEntry: Codable {
        let tmdbIDs: [Int]
        let lastFetched: Date
    }

    struct CatalogEntry: Codable, Sendable {
        let items: [SeerrMedia]
        let totalPages: Int
        let lastFetched: Date
    }

    init() {
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = caches.appendingPathComponent("FilterCache", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        // One-shot migration sweep: if the previous UserDefaults-backed
        // cache left entries in the app's domain, wipe them so the
        // 1 MB cap doesn't keep tripping on app launches that haven't
        // yet rotated the offending keys.
        Self.purgeLegacyDefaults()
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key).appendingPathExtension("json")
    }

    private func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, key: String) {
        let url = fileURL(for: key)
        guard let data = try? JSONEncoder().encode(value) else { return }
        // Atomic write so a crash mid-flush leaves the previous file
        // intact rather than producing a half-written truncated blob
        // that would make the next decode fail.
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Home Smart Filter (resolved JellyfinItems)

    func homeFilterItems(filterKey: String) -> [JellyfinItem]? {
        read(HomeItemsEntry.self, key: Self.homeItemsPrefix + filterKey)?.items
    }

    func setHomeFilterItems(_ items: [JellyfinItem], filterKey: String) {
        let entry = HomeItemsEntry(items: items, lastFetched: Date())
        write(entry, key: Self.homeItemsPrefix + filterKey)
    }

    // MARK: - Smart Filter (TMDB ids)

    func smartFilterIDs(providerID: Int, region: String) -> [Int]? {
        read(SmartEntry.self, key: Self.smartIDPrefix + "\(providerID)-\(region)")?.tmdbIDs
    }

    func setSmartFilterIDs(_ ids: [Int], providerID: Int, region: String) {
        let entry = SmartEntry(tmdbIDs: ids, lastFetched: Date())
        write(entry, key: Self.smartIDPrefix + "\(providerID)-\(region)")
    }

    // MARK: - Catalog Filter Page 1

    func catalogPage(filterKey: String) -> CatalogEntry? {
        read(CatalogEntry.self, key: Self.catalogPrefix + filterKey)
    }

    func setCatalogPage(_ items: [SeerrMedia], totalPages: Int, filterKey: String) {
        let entry = CatalogEntry(items: items, totalPages: totalPages, lastFetched: Date())
        write(entry, key: Self.catalogPrefix + filterKey)
    }

    // MARK: - Bulk invalidation

    /// Clears every cache slice — called on profile switch / logout
    /// so a new user doesn't see the previous user's filter results.
    func clearAll() {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }
        for url in entries {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Wipe any leftover entries from the old `UserDefaults`-backed
    /// implementation. Runs once on first instantiation. Safe to keep
    /// indefinitely — once the keys are gone the loop is a no-op.
    private static func purgeLegacyDefaults() {
        let defaults = UserDefaults.standard
        let prefixes = ["FilterCache.homeItems.", "FilterCache.smart.", "FilterCache.catalog."]
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
