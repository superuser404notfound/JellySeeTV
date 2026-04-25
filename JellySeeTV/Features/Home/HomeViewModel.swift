import SwiftUI

@Observable
final class HomeViewModel {
    var rows: [HomeRowData] = []
    var tagRows: [HomeTagRowData] = []
    var isLoading = true
    var errorMessage: String?
    var rowConfigs: [HomeRowConfig] = []
    var needsReload = false
    /// Sample backdrop URL per streaming-provider TMDB id, populated
    /// from a one-shot Jellyfin Studios query so each provider tile
    /// can show a hero image of an actual library item rather than a
    /// flat dark plate. Empty values are kept as `nil` so the tile
    /// gracefully falls back to the logo-only style.
    var providerBackdrops: [Int: URL] = [:]

    /// Timestamp of the last successful loadContent(). Used by the
    /// view's onAppear to decide whether enough time has passed to
    /// refresh — otherwise new server-side content (Latest Movies,
    /// Latest Series, etc.) never shows up until the app restarts.
    var lastLoadedAt: Date?

    private let libraryService: JellyfinLibraryServiceProtocol
    private let imageService: JellyfinImageService
    private let userID: String
    private var libraries: [JellyfinLibrary] = []

    init(
        libraryService: JellyfinLibraryServiceProtocol,
        imageService: JellyfinImageService,
        userID: String
    ) {
        self.libraryService = libraryService
        self.imageService = imageService
        self.userID = userID
        self.rowConfigs = HomeRowConfig.loadFromStorage()
    }

    func loadContent() async {
        let isFirstLoad = rows.isEmpty && tagRows.isEmpty
        if isFirstLoad {
            isLoading = true
        }
        errorMessage = nil

        do {
            libraries = try await libraryService.getLibraries(userID: userID)

            let enabledRows = rowConfigs
                .filter(\.isEnabled)
                .sorted { $0.sortOrder < $1.sortOrder }

            var newRows: [HomeRowData] = []
            var newTagRows: [HomeTagRowData] = []

            for config in enabledRows {
                if config.type.isDiscoverProviderRow {
                    // Hardcoded data — nothing to fetch. The HomeView
                    // renders the row directly from CatalogProviders.
                    continue
                }
                if config.type.isTagRow {
                    if let tagRow = await loadTagRow(type: config.type) {
                        if !tagRow.tags.isEmpty {
                            newTagRows.append(tagRow)
                        }
                    }
                } else {
                    if let rowData = await loadRow(type: config.type) {
                        if !rowData.items.isEmpty {
                            newRows.append(rowData)
                        }
                    }
                }
            }

            // Atomic swap -- old images stay visible until new data is ready.
            // ForEach diffs by HomeRowData.id (stable) so AsyncImage
            // subviews are reused when rows are refetched; no .id() on the
            // LazyVStack, which would otherwise recreate the whole subtree
            // and force every AsyncImage back into its empty phase.
            rows = newRows
            tagRows = newTagRows
            isLoading = false
            lastLoadedAt = .now

            // Best-effort: fan out one Studios query per provider so
            // the streaming-provider row can render a sample backdrop
            // from the local library. Failures and gaps in metadata
            // are tolerated — the tile falls back to the logo-only
            // style for any provider that doesn't resolve.
            Task { await loadProviderBackdrops() }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadProviderBackdrops() async {
        let providers = CatalogProviders.networks
        // Stage 1: collect a sample item per provider in parallel.
        // imageService isn't Sendable, so URL construction happens
        // back on MainActor in stage 2 — the task group only carries
        // the JellyfinItem (which is Sendable) across the boundary.
        let pairs: [(Int, JellyfinItem)] = await withTaskGroup(
            of: (Int, JellyfinItem?).self,
            returning: [(Int, JellyfinItem)].self
        ) { group in
            for provider in providers {
                group.addTask { [libraryService, userID] in
                    let query = ItemQuery(
                        includeItemTypes: [.movie, .series],
                        sortBy: "Random",
                        limit: 1,
                        studioNames: provider.jellyfinStudioNames
                    )
                    let item = try? await libraryService.getItems(userID: userID, query: query).items.first
                    return (provider.id, item)
                }
            }
            var collected: [(Int, JellyfinItem)] = []
            for await (id, item) in group {
                if let item { collected.append((id, item)) }
            }
            return collected
        }
        for (id, item) in pairs {
            if let url = imageService.backdropURL(for: item) ?? imageService.posterURL(for: item) {
                providerBackdrops[id] = url
            }
        }
    }

    private func loadRow(type: HomeRowType) async -> HomeRowData? {
        do {
            let items: [JellyfinItem]

            switch type {
            case .continueWatching:
                let response = try await libraryService.getResumeItems(userID: userID, mediaType: "Video", limit: 16)
                items = response.items

            case .nextUp:
                let response = try await libraryService.getNextUp(userID: userID, seriesID: nil, limit: 16)
                items = response.items

            case .latestMovies:
                // Native /Items/Latest for Jellyfin parity — whatever
                // order the Jellyfin web UI shows is what JellySeeTV
                // shows. ParentId omitted so users with multiple
                // movie libraries (Movies + Documentaries + Kids …)
                // see fresh content from every source; without the
                // parent-id hint we MUST pass IncludeItemTypes=Movie,
                // otherwise Jellyfin returns a mix of movies,
                // series, and music jumbled into one row.
                items = try await libraryService.getLatestMedia(
                    userID: userID,
                    parentID: nil,
                    includeItemTypes: [.movie],
                    limit: 16
                )

            case .latestShows:
                // Same treatment as latestMovies — /Items/Latest
                // across every accessible library, typed down to
                // Series so we don't get movies/music mixed in.
                items = try await libraryService.getLatestMedia(
                    userID: userID,
                    parentID: nil,
                    includeItemTypes: [.series],
                    limit: 16
                )

            case .allMovies:
                let query = ItemQuery(
                    includeItemTypes: [.movie],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 30
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .allSeries:
                let query = ItemQuery(
                    includeItemTypes: [.series],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 30
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .favorites:
                let query = ItemQuery(
                    includeItemTypes: [.movie, .series, .boxSet],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 30,
                    isFavorite: true
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .topRatedMovies:
                let query = ItemQuery(
                    includeItemTypes: [.movie],
                    sortBy: "CommunityRating",
                    sortOrder: "Descending",
                    limit: 20
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .topRatedShows:
                let query = ItemQuery(
                    includeItemTypes: [.series],
                    sortBy: "CommunityRating",
                    sortOrder: "Descending",
                    limit: 20
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .recentlyAdded:
                let query = ItemQuery(
                    includeItemTypes: [.movie, .series],
                    sortBy: "DateCreated",
                    sortOrder: "Descending",
                    limit: 20
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .collections:
                let query = ItemQuery(
                    includeItemTypes: [.boxSet],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 30
                )
                let response = try await libraryService.getItems(userID: userID, query: query)
                items = response.items

            case .genres, .discoverProviders:
                return nil
            }

            return HomeRowData(type: type, items: items)
        } catch {
            return nil
        }
    }

    private func loadTagRow(type: HomeRowType) async -> HomeTagRowData? {
        do {
            let tags: [NamedItem]
            switch type {
            case .genres:
                let allGenres = try await libraryService.getGenres(userID: userID)
                tags = allGenres.filter { GenreFilter.isPrimary($0.name) }
            default:
                return nil
            }

            // Fetch one item per tag in parallel for matching backdrops
            let tagItems: [(String, JellyfinItem?)] = await withTaskGroup(
                of: (String, JellyfinItem?).self,
                returning: [(String, JellyfinItem?)].self
            ) { group in
                for tag in tags {
                    group.addTask {
                        let query = ItemQuery(
                            includeItemTypes: [.movie, .series],
                            sortBy: "Random",
                            limit: 1,
                            genres: [tag.name]
                        )
                        let item = try? await self.libraryService.getItems(userID: self.userID, query: query).items.first
                        return (tag.id, item)
                    }
                }
                var results: [(String, JellyfinItem?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            // Build cards on MainActor (image URL construction needs it)
            let itemMap = Dictionary(uniqueKeysWithValues: tagItems)
            let cardData: [TagCardData] = tags.map { tag in
                let item = itemMap[tag.id].flatMap { $0 }
                let backdropURL = item.flatMap { imageService.backdropURL(for: $0) ?? imageService.posterURL(for: $0) }
                return TagCardData(
                    id: tag.id,
                    name: tag.name,
                    backdropURL: backdropURL,
                    logoURL: nil,
                    isStudio: false
                )
            }

            return HomeTagRowData(type: type, tags: cardData)
        } catch {
            return nil
        }
    }

    func imageURL(for item: JellyfinItem, rowType: HomeRowType) -> URL? {
        if rowType.usesBackdrop {
            // For continue watching / next up: use episode thumbnail first
            if item.type == .episode {
                return imageService.episodeThumbnailURL(for: item)
            }
            return imageService.backdropURL(for: item) ?? imageService.posterURL(for: item)
        }
        return imageService.posterURL(for: item)
    }

    func reloadConfig() {
        rowConfigs = HomeRowConfig.loadFromStorage()
    }

    /// Returns the ordered list of all sections (media rows + tag rows + discover) in config order
    func orderedSections() -> [HomeSection] {
        let enabledConfigs = rowConfigs
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }

        return enabledConfigs.compactMap { config in
            if config.type.isDiscoverProviderRow {
                return .discoverProviders
            }
            if config.type.isTagRow {
                if let tagRow = tagRows.first(where: { $0.type == config.type }) {
                    return .tags(tagRow)
                }
            } else {
                if let row = rows.first(where: { $0.type == config.type }) {
                    return .media(row)
                }
            }
            return nil
        }
    }
}

enum HomeSection: Identifiable {
    case media(HomeRowData)
    case tags(HomeTagRowData)
    case discoverProviders

    var id: String {
        switch self {
        case .media(let data): data.id
        case .tags(let data): data.id
        case .discoverProviders: "discoverProviders"
        }
    }
}

struct HomeRowData: Identifiable, Sendable {
    let type: HomeRowType
    let items: [JellyfinItem]

    var id: String { type.rawValue }
}

struct HomeTagRowData: Identifiable, Sendable {
    let type: HomeRowType
    let tags: [TagCardData]

    var id: String { type.rawValue }
}
