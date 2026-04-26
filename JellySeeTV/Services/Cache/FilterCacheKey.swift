import Foundation

/// Single source of truth for the keys under which `FilterCache`
/// stores filter results. Both *writers* (Home/Catalog precomputes,
/// the grid views revalidating on tap) and *readers* (the empty-tile
/// hide filters in HomeView/CatalogDiscoverView, the grid views'
/// init-time hydration) go through these factories so a key-format
/// change can never make a reader miss a writer's blob and silently
/// degrade to "loading flash on every tap".
///
/// Two namespaces, kept separate because they map to two different
/// cache slices on `FilterCache`:
///
/// - **Home**: keys passed to
///   `FilterCache.homeFilterItems(filterKey:)` /
///   `setHomeFilterItems(_:filterKey:)`. Stores resolved
///   `[JellyfinItem]` lists for tiles on the Home screen.
///
/// - **Catalog**: keys passed to `FilterCache.catalogPage(filterKey:)`
///   / `setCatalogPage(_:totalPages:filterKey:)`. Stores
///   `[SeerrMedia]` lists for Catalog tiles.
/// Pure string builders — `nonisolated` throughout so callers in
/// detached tasks (the catalog precompute fan-out, the home provider
/// resolver) can use them without an actor hop. The project's default
/// MainActor isolation would otherwise pin every helper here to the
/// main actor and force the few precompute paths to round-trip.
enum FilterCacheKey {
    enum Home {
        /// Local-library smart filter for a streaming-provider tile
        /// (Netflix, Disney+, …). Region is part of the key because
        /// TMDB watch-providers are region-specific — a Disney+ tile
        /// in DE resolves to a different lineup than in US.
        nonisolated static func provider(id: Int, region: String) -> String {
            "home-\(id)-\(region)"
        }

        /// Local-library genre filter (Action, Comedy, …). Genre name
        /// is the differentiator since Jellyfin queries by name, not
        /// id.
        nonisolated static func genre(name: String) -> String {
            "home-genre-\(name)"
        }

        /// Generic tag filter — fallback for HomeRowType cases
        /// without their own dedicated key.
        nonisolated static func tag(name: String) -> String {
            "home-tag-\(name)"
        }
    }

    enum Catalog {
        nonisolated static func streamingService(watchProviderID: Int, region: String) -> String {
            "streamingService-\(watchProviderID)-\(region)"
        }

        nonisolated static func tvNetwork(id: Int) -> String {
            "tvNetwork-\(id)"
        }

        nonisolated static func movieStudio(id: Int) -> String {
            "movieStudio-\(id)"
        }

        nonisolated static func movieGenre(id: Int) -> String {
            "movieGenre-\(id)"
        }

        nonisolated static func tvGenre(id: Int) -> String {
            "tvGenre-\(id)"
        }
    }
}
