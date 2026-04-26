import Foundation

/// Selector for a Jellyseerr "filtered discover" page — genre,
/// streaming network, or production studio. Plumbed through the
/// CatalogFilteredGridView's navigation destination so the grid
/// knows which Seerr endpoint to hit and what title to render at
/// the top.
enum CatalogFilter: Hashable, Sendable {
    case movieGenre(id: Int, name: String)
    case tvGenre(id: Int, name: String)
    case movieStudio(id: Int, name: String)
    case tvNetwork(id: Int, name: String)
    /// Live "what's currently streaming on this service" filter
    /// backed by TMDB's watch-providers data. Returns both movies
    /// and TV — preferred over `.tvNetwork` for streamers that span
    /// both (Disney+, Netflix, Apple TV+, …) so a Catalog tap on
    /// the Disney+ tile doesn't hide every Disney+ movie behind a
    /// TV-only network filter.
    case streamingService(tmdbWatchProviderID: Int, name: String, region: String)

    var displayName: String {
        switch self {
        case .movieGenre(_, let name),
             .tvGenre(_, let name),
             .movieStudio(_, let name),
             .tvNetwork(_, let name),
             .streamingService(_, let name, _):
            return name
        }
    }

    /// Stable identifier used as the FilterCache key. Region is
    /// embedded for streaming services because TMDB watch-providers
    /// are region-specific — the same Disney+ tile resolves to a
    /// different lineup in DE vs US, so the cached pages must be
    /// scoped to the region they came from.
    var cacheKey: String {
        switch self {
        case .movieGenre(let id, _): return "movieGenre-\(id)"
        case .tvGenre(let id, _): return "tvGenre-\(id)"
        case .movieStudio(let id, _): return "movieStudio-\(id)"
        case .tvNetwork(let id, _): return "tvNetwork-\(id)"
        case .streamingService(let id, _, let region): return "streamingService-\(id)-\(region)"
        }
    }
}
