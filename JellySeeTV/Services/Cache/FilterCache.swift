import Foundation

/// Persistent cache for the result sets behind the home + catalog
/// filter tiles (streaming providers, genres, studios). Two slices:
///
/// - **smartFilterIDs**: the resolved TMDB id list for a Home-page
///   provider tile. The home view matches these against the local
///   Jellyfin library to render its grid; caching the id list lets
///   the second tap on Disney+ render instantly while a fresh fetch
///   refreshes the cache underneath.
///
/// - **catalogPage**: the first page of items for a Catalog filter
///   tile (genre / studio / streamingService / network). Used to
///   make the catalog grid show the most-recent state immediately on
///   re-entry; pagination beyond page 1 still hits the network on
///   demand.
///
/// Stale-while-revalidate is intentional. Each refresh fully replaces
/// the cached value with the fresh response, so anything that left
/// the provider's lineup since last visit drops out automatically —
/// no per-item expiry tracking needed.
///
/// Backed by UserDefaults. The cached payloads are small (a couple
/// hundred ints for the smart filter, ~40 small SeerrMedia for a
/// catalog page) so a single defaults blob per key stays well under
/// the practical UserDefaults size limit.
actor FilterCache {
    static let shared = FilterCache()

    private let defaults = UserDefaults.standard
    private static let smartFilterPrefix = "FilterCache.smart."
    private static let catalogPrefix = "FilterCache.catalog."

    private struct SmartEntry: Codable {
        let tmdbIDs: [Int]
        let lastFetched: Date
    }

    struct CatalogEntry: Codable, Sendable {
        let items: [SeerrMedia]
        let totalPages: Int
        let lastFetched: Date
    }

    // MARK: - Smart Filter (Home — TMDB watch-provider id list)

    func smartFilterIDs(providerID: Int, region: String) -> [Int]? {
        let key = Self.smartFilterPrefix + "\(providerID)-\(region)"
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(SmartEntry.self, from: data)
        else { return nil }
        return entry.tmdbIDs
    }

    func setSmartFilterIDs(_ ids: [Int], providerID: Int, region: String) {
        let key = Self.smartFilterPrefix + "\(providerID)-\(region)"
        let entry = SmartEntry(tmdbIDs: ids, lastFetched: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: - Catalog Filter Page 1

    func catalogPage(filterKey: String) -> CatalogEntry? {
        let key = Self.catalogPrefix + filterKey
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(CatalogEntry.self, from: data)
        else { return nil }
        return entry
    }

    func setCatalogPage(_ items: [SeerrMedia], totalPages: Int, filterKey: String) {
        let key = Self.catalogPrefix + filterKey
        let entry = CatalogEntry(items: items, totalPages: totalPages, lastFetched: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: key)
    }
}
