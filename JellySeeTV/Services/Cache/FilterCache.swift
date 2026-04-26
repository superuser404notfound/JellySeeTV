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
/// Backed by `UserDefaults` directly. UserDefaults reads + writes are
/// thread-safe at the system level, so no internal lock is required —
/// the class is `@unchecked Sendable` because nothing mutable is
/// stored beyond the UserDefaults pointer. Synchronous API
/// throughout: SwiftUI views can hit the cache from inside
/// `body`-adjacent code without an actor hop, which is what makes
/// the cached display appear in the same render pass instead of one
/// frame later.
final class FilterCache: @unchecked Sendable {
    static let shared = FilterCache()

    private let defaults = UserDefaults.standard
    private static let homeItemsPrefix = "FilterCache.homeItems."
    private static let smartIDPrefix = "FilterCache.smart."
    private static let catalogPrefix = "FilterCache.catalog."

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

    // MARK: - Home Smart Filter (resolved JellyfinItems)

    func homeFilterItems(filterKey: String) -> [JellyfinItem]? {
        let key = Self.homeItemsPrefix + filterKey
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(HomeItemsEntry.self, from: data)
        else { return nil }
        return entry.items
    }

    func setHomeFilterItems(_ items: [JellyfinItem], filterKey: String) {
        let key = Self.homeItemsPrefix + filterKey
        let entry = HomeItemsEntry(items: items, lastFetched: Date())
        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: key)
    }

    // MARK: - Smart Filter (TMDB ids)

    func smartFilterIDs(providerID: Int, region: String) -> [Int]? {
        let key = Self.smartIDPrefix + "\(providerID)-\(region)"
        guard let data = defaults.data(forKey: key),
              let entry = try? JSONDecoder().decode(SmartEntry.self, from: data)
        else { return nil }
        return entry.tmdbIDs
    }

    func setSmartFilterIDs(_ ids: [Int], providerID: Int, region: String) {
        let key = Self.smartIDPrefix + "\(providerID)-\(region)"
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

    // MARK: - Bulk invalidation

    /// Clears every cache slice — called on profile switch / logout
    /// so a new user doesn't see the previous user's filter results.
    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(Self.homeItemsPrefix)
                || key.hasPrefix(Self.smartIDPrefix)
                || key.hasPrefix(Self.catalogPrefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
