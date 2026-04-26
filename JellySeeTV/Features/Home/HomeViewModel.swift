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

    /// Resolved-item count per streaming provider, keyed by
    /// `provider.id`. Populated by the background precompute pass —
    /// the empty-tile-hide filter on the home view reads from here
    /// to drop providers whose library matches resolve to zero
    /// without waiting for the user to tap each one.
    var providerItemCounts: [Int: Int] = [:]

    /// Guards against concurrent / repeated precompute runs within
    /// the same session — re-resolving every provider on every Home
    /// re-appearance would hammer Seerr for ~100 calls and add
    /// nothing the user can perceive.
    private var providerCountsComputedAt: Date?

    /// Same throttle as `providerCountsComputedAt`, but for the
    /// genre-tile pre-warm pass. The grids themselves still revalidate
    /// against the server when opened, this just means the *first*
    /// frame after a tap is already painted from the file cache.
    private var genreCachesComputedAt: Date?

    /// Handles for the background side-effects `loadContent` kicks
    /// off. Held so we can cancel them when the view model is torn
    /// down (profile switch, tab destruction) or when `loadContent`
    /// is re-entered before the previous fan-out finished — without
    /// that, an orphaned VM keeps fetching against the server and
    /// writing into FilterCache long after the UI it backed is gone.
    private var backdropTask: Task<Void, Never>?
    private var providerCountsTask: Task<Void, Never>?
    private var genreCachesTask: Task<Void, Never>?

    /// Timestamp of the last successful loadContent(). Used by the
    /// view's onAppear to decide whether enough time has passed to
    /// refresh — otherwise new server-side content (Latest Movies,
    /// Latest Series, etc.) never shows up until the app restarts.
    var lastLoadedAt: Date?

    private let libraryService: JellyfinLibraryServiceProtocol
    private let imageService: JellyfinImageService
    private let discoverService: SeerrDiscoverServiceProtocol?
    private let userID: String

    init(
        libraryService: JellyfinLibraryServiceProtocol,
        imageService: JellyfinImageService,
        discoverService: SeerrDiscoverServiceProtocol? = nil,
        userID: String
    ) {
        self.libraryService = libraryService
        self.imageService = imageService
        self.discoverService = discoverService
        self.userID = userID
        self.rowConfigs = HomeRowConfig.loadFromStorage()
    }

    func loadContent() async {
        let isFirstLoad = rows.isEmpty && tagRows.isEmpty
        if isFirstLoad {
            isLoading = true
        }
        errorMessage = nil

        let enabledRows = rowConfigs
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }

        // Fan out every row's network call in parallel. The
        // sequential `for await` walk used to mean each row started
        // only after the previous one returned, so a 7-row config
        // took roughly 7× the slowest call. Tasks come back in
        // completion order; orderedSections() drives display order
        // from the config sortOrder, so the source arrays don't
        // need to be ordered.
        enum RowResult: Sendable {
            case media(HomeRowData)
            case tag(HomeTagRowData)
            case empty
        }

        // Capture row-type predicates on MainActor before crossing
        // into the task group — HomeRowType is MainActor-isolated
        // under the project's default-isolation rule, so reading
        // .isTagRow from a non-isolated closure would otherwise be
        // rejected.
        let plan: [(type: HomeRowType, isTag: Bool)] = enabledRows.compactMap { config in
            if config.type.isDiscoverProviderRow {
                // Hardcoded data — nothing to fetch. The HomeView
                // renders the row directly from CatalogProviders.
                return nil
            }
            return (config.type, config.type.isTagRow)
        }

        let results = await withTaskGroup(of: RowResult.self, returning: [RowResult].self) { group in
            for entry in plan {
                group.addTask { [weak self] in
                    guard let self else { return .empty }
                    if entry.isTag {
                        if let tagRow = await self.loadTagRow(type: entry.type), !tagRow.tags.isEmpty {
                            return .tag(tagRow)
                        }
                    } else {
                        if let rowData = await self.loadRow(type: entry.type), !rowData.items.isEmpty {
                            return .media(rowData)
                        }
                    }
                    return .empty
                }
            }
            var collected: [RowResult] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var newRows: [HomeRowData] = []
        var newTagRows: [HomeTagRowData] = []
        for result in results {
            switch result {
            case .media(let row): newRows.append(row)
            case .tag(let row): newTagRows.append(row)
            case .empty: break
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

        // Cancel any previous fan-outs before kicking new ones off:
        // a rapid profile switch / notification-driven reload would
        // otherwise stack 2× the network calls and 2× the FilterCache
        // writes, with the older task scribbling stale data over the
        // newer one if it finished last.
        backdropTask?.cancel()
        providerCountsTask?.cancel()
        genreCachesTask?.cancel()

        // Best-effort: fan out one Studios query per provider so
        // the streaming-provider row can render a sample backdrop
        // from the local library. Failures and gaps in metadata
        // are tolerated — the tile falls back to the logo-only
        // style for any provider that doesn't resolve.
        backdropTask = Task { [weak self] in
            await self?.loadProviderBackdrops()
        }
        // Pre-resolve every provider tile in the background so the
        // empty-tile-hide pass on the home view has data to act on
        // *before* the user has tapped each one. Throttled to one
        // run per session.
        providerCountsTask = Task { [weak self] in
            await self?.precomputeProviderCounts()
        }
        // Pre-warm the genre tile grids the same way: one Studios
        // query per genre so the first tap renders straight from the
        // cache instead of paying a network roundtrip.
        genreCachesTask = Task { [weak self] in
            await self?.precomputeGenreCaches()
        }
    }

    /// Resolves every CatalogProviders.networks tile against the
    /// local library + (where available) TMDB watch-providers, in
    /// the background, so the home-view filter can drop empty
    /// tiles automatically. Each provider's full result list is
    /// also written to FilterCache so a subsequent tap renders the
    /// grid synchronously.
    ///
    /// Throttled to one run per session — re-running every Home
    /// re-appearance would fire ~110 Seerr calls and add nothing
    /// the user can perceive in that window. Storage state (cache
    /// + counts dict) survives across appearances anyway.
    func precomputeProviderCounts() async {
        if providerCountsComputedAt != nil { return }
        providerCountsComputedAt = Date()

        let region = Locale.current.region?.identifier ?? "US"
        let lib = libraryService
        let disc = discoverService
        let uid = userID

        // Build the TMDB map on MainActor first — JellyfinItem.tmdbID
        // and CatalogProviders.networks are both MainActor-isolated
        // under the project's default isolation, so we have to read
        // them here before handing the values to a detached task.
        let allItemsQuery = ItemQuery(
            includeItemTypes: [.movie, .series],
            sortBy: "SortName",
            sortOrder: "Ascending",
            limit: 10000
        )
        let allItems = (try? await libraryService.getItems(
            userID: userID, query: allItemsQuery
        ).items) ?? []

        var tmdbMap: [Int: JellyfinItem] = [:]
        for item in allItems {
            if let id = item.tmdbID { tmdbMap[id] = item }
        }
        // Snapshot only the fields the resolve pass needs into a
        // plain Sendable struct — CatalogProvider itself is
        // MainActor-isolated under the project default, so we can't
        // hand the struct directly to a detached task.
        let providerInfos: [ProviderResolveInfo] = CatalogProviders.networks.map {
            ProviderResolveInfo(
                id: $0.id,
                studioNames: $0.jellyfinStudioNames,
                watchProviderID: $0.tmdbWatchProviderID
            )
        }
        let mapForTask = tmdbMap

        // Resolve passes runs in a detached task so the task-group
        // closures it spawns don't inherit MainActor isolation.
        let resolved: [(Int, [JellyfinItem])] = await Task.detached(priority: .utility) {
            await withTaskGroup(
                of: (Int, [JellyfinItem]).self,
                returning: [(Int, [JellyfinItem])].self
            ) { group in
                var iter = providerInfos.makeIterator()
                let maxConcurrent = 4

                for _ in 0..<maxConcurrent {
                    guard let info = iter.next() else { break }
                    group.addTask {
                        let items = await Self.resolveProviderItems(
                            info: info, region: region,
                            tmdbMap: mapForTask,
                            libraryService: lib, discoverService: disc, userID: uid
                        )
                        return (info.id, items)
                    }
                }
                var collected: [(Int, [JellyfinItem])] = []
                while let result = await group.next() {
                    collected.append(result)
                    if let next = iter.next() {
                        group.addTask {
                            let items = await Self.resolveProviderItems(
                                info: next, region: region,
                                tmdbMap: mapForTask,
                                libraryService: lib, discoverService: disc, userID: uid
                            )
                            return (next.id, items)
                        }
                    }
                }
                return collected
            }
        }.value

        // MainActor pass: write counts + cache + sample backdrop
        // for each provider.
        for (providerID, items) in resolved {
            providerItemCounts[providerID] = items.count
            FilterCache.shared.setHomeFilterItems(
                items,
                filterKey: FilterCacheKey.Home.provider(id: providerID, region: region)
            )
            // Backfill the backdrop only if the fast studio-only
            // pass didn't already set one — the precompute resolver
            // includes watch-provider matches, so it can find a
            // sample for tiles whose Studios tag in the library
            // doesn't match (Paramount+ in particular).
            if providerBackdrops[providerID] == nil,
               let sample = items.first,
               let url = imageService.backdropURL(for: sample)
                   ?? imageService.posterURL(for: sample) {
                providerBackdrops[providerID] = url
            }
        }
    }

    /// Pre-warms FilterCache for every genre tile currently on the
    /// home page so the first tap on `Action`, `Comedy`, … renders
    /// straight from disk instead of going through a Jellyfin Studios
    /// roundtrip. Mirrors the provider precompute pattern: detached
    /// task group with a small concurrency cap, throttled to one run
    /// per session. The grid views still refresh against the server
    /// when opened (stale-while-revalidate), this just paints the
    /// first frame instantly. Gated by `genreCachesComputedAt` so
    /// repeated Home re-appearances within a session don't re-run.
    func precomputeGenreCaches() async {
        if genreCachesComputedAt != nil { return }
        // Wait until tagRows is populated. loadContent + this method
        // are both kicked off from the same Task.detached point so
        // they can race; if loadContent hasn't finished yet, just
        // bail and let the next caller (or the next Home appearance)
        // pick it up. Cheap enough that we don't bother retrying.
        let genreNames: [String] = tagRows
            .filter { $0.type == .genres }
            .flatMap { $0.tags.map(\.name) }
        if genreNames.isEmpty { return }
        genreCachesComputedAt = Date()

        let lib = libraryService
        let uid = userID

        let resolved: [(String, [JellyfinItem])] = await Task.detached(priority: .utility) {
            await withTaskGroup(
                of: (String, [JellyfinItem]).self,
                returning: [(String, [JellyfinItem])].self
            ) { group in
                var iter = genreNames.makeIterator()
                let maxConcurrent = 4

                func enqueue(_ name: String) {
                    group.addTask {
                        let query = ItemQuery(
                            includeItemTypes: [.movie, .series],
                            sortBy: "SortName",
                            sortOrder: "Ascending",
                            limit: 50,
                            genres: [name]
                        )
                        let items = (try? await lib.getItems(
                            userID: uid, query: query
                        ).items) ?? []
                        return (name, items)
                    }
                }

                for _ in 0..<maxConcurrent {
                    guard let next = iter.next() else { break }
                    enqueue(next)
                }
                var collected: [(String, [JellyfinItem])] = []
                while let result = await group.next() {
                    collected.append(result)
                    if let next = iter.next() { enqueue(next) }
                }
                return collected
            }
        }.value

        // Hop back to MainActor for the cache writes — FilterCache.shared
        // is non-isolated but the detached closure can't see that under
        // the project's strict-concurrency settings, so we collect the
        // results first and persist here.
        for (name, items) in resolved where !items.isEmpty {
            FilterCache.shared.setHomeFilterItems(
                items, filterKey: FilterCacheKey.Home.genre(name: name)
            )
        }
    }

    /// Sendable snapshot of the fields `resolveProviderItems` reads
    /// off a `CatalogProvider`. Needed because CatalogProvider
    /// itself is MainActor-isolated under the project default and
    /// the resolve pass runs in a detached task.
    struct ProviderResolveInfo: Sendable {
        let id: Int
        let studioNames: [String]
        let watchProviderID: Int?
    }

    /// Resolves a single provider's library items: studio-name match
    /// (always) plus TMDB watch-provider augment (when the provider
    /// has a watch-provider id). Returns the merged + deduped list,
    /// alphabetically ordered after the studio matches. Static so
    /// the precompute task group doesn't have to capture `self`.
    private static func resolveProviderItems(
        info: ProviderResolveInfo,
        region: String,
        tmdbMap: [Int: JellyfinItem],
        libraryService: JellyfinLibraryServiceProtocol,
        discoverService: SeerrDiscoverServiceProtocol?,
        userID: String
    ) async -> [JellyfinItem] {
        let studioQuery = ItemQuery(
            includeItemTypes: [.movie, .series],
            sortBy: "SortName",
            sortOrder: "Ascending",
            limit: 200,
            studioNames: info.studioNames
        )
        let studioItems = (try? await libraryService.getItems(
            userID: userID, query: studioQuery
        ).items) ?? []

        var phase2Items: [JellyfinItem] = []
        if let watchID = info.watchProviderID, let discover = discoverService {
            var providerTmdbIDs: Set<Int> = []
            await withTaskGroup(of: Set<Int>.self) { group in
                for page in 1...5 {
                    group.addTask {
                        let movies = (try? await discover.moviesByWatchProvider(
                            providerID: watchID, region: region, page: page
                        ))?.results.map(\.id) ?? []
                        let tv = (try? await discover.tvByWatchProvider(
                            providerID: watchID, region: region, page: page
                        ))?.results.map(\.id) ?? []
                        return Set(movies + tv)
                    }
                }
                for await ids in group { providerTmdbIDs.formUnion(ids) }
            }
            phase2Items = providerTmdbIDs.compactMap { tmdbMap[$0] }
        }

        let phase1IDs = Set(studioItems.map(\.id))
        let extras = phase2Items
            .filter { !phase1IDs.contains($0.id) }
            .sorted { $0.name < $1.name }
        return studioItems + extras
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
                return TagCardData(id: tag.id, name: tag.name, backdropURL: backdropURL)
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
