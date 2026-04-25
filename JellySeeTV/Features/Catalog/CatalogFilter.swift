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

    var displayName: String {
        switch self {
        case .movieGenre(_, let name),
             .tvGenre(_, let name),
             .movieStudio(_, let name),
             .tvNetwork(_, let name):
            return name
        }
    }
}
