import Foundation
import Observation

@MainActor
@Observable
final class CatalogViewModel {

    struct PagedSection {
        var items: [SeerrMedia] = []
        var currentPage: Int = 0
        var totalPages: Int = 1
        var isLoading = false

        var hasMore: Bool { currentPage < totalPages }
    }

    var trending = PagedSection()
    var popularMovies = PagedSection()
    var popularTV = PagedSection()
    var upcomingMovies = PagedSection()
    var upcomingTV = PagedSection()
    /// Curated, populated genre lists from
    /// `/discover/genreslider/movie` and `/discover/genreslider/tv`.
    /// Each entry has a few backdrop paths so the genre tile can
    /// show a hero image instead of a flat capsule.
    var movieGenres: [SeerrGenreSlide] = []
    var tvGenres: [SeerrGenreSlide] = []
    /// Sample backdrop paths per network/studio TMDB id — populated
    /// in the background after the first discover load by hitting
    /// `/discover/tv/network/{id}` (or `…/movies/studio/{id}`) with
    /// page 1 and grabbing the first result's backdrop. Lets the
    /// provider tiles show a hero image of an actual show on that
    /// service instead of a flat dark plate.
    var networkBackdrops: [Int: String] = [:]
    var studioBackdrops: [Int: String] = [:]
    var myRequests: [SeerrRequest] = []

    /// Per-request enrichment keyed by tmdbID. Populated in the
    /// background after loadMyRequests returns so the list can
    /// switch from "#42" placeholders to "Dune · 2021" with a
    /// poster as soon as the detail calls come back.
    var requestMovieDetails: [Int: SeerrMovieDetail] = [:]
    var requestTVDetails: [Int: SeerrTVDetail] = [:]

    var isLoadingDiscover = false
    var isLoadingRequests = false
    var errorMessage: String?

    private let discoverService: SeerrDiscoverServiceProtocol
    private let requestService: SeerrRequestServiceProtocol
    private let mediaService: SeerrMediaServiceProtocol

    init(
        discoverService: SeerrDiscoverServiceProtocol,
        requestService: SeerrRequestServiceProtocol,
        mediaService: SeerrMediaServiceProtocol
    ) {
        self.discoverService = discoverService
        self.requestService = requestService
        self.mediaService = mediaService
    }

    // MARK: - Request enrichment

    func title(for request: SeerrRequest) -> String? {
        guard let tmdbID = request.media?.tmdbId else { return nil }
        switch request.type {
        case .movie:  return requestMovieDetails[tmdbID]?.title
        case .tv:     return requestTVDetails[tmdbID]?.name
        case .person: return nil
        }
    }

    func year(for request: SeerrRequest) -> String? {
        guard let tmdbID = request.media?.tmdbId else { return nil }
        switch request.type {
        case .movie:  return requestMovieDetails[tmdbID]?.displayYear
        case .tv:     return requestTVDetails[tmdbID]?.displayYear
        case .person: return nil
        }
    }

    func posterURL(for request: SeerrRequest) -> URL? {
        guard let tmdbID = request.media?.tmdbId else { return nil }
        let path: String?
        switch request.type {
        case .movie:  path = requestMovieDetails[tmdbID]?.posterPath
        case .tv:     path = requestTVDetails[tmdbID]?.posterPath
        case .person: path = nil
        }
        return SeerrImageURL.poster(path: path, size: .w342)
    }

    func loadDiscover() async {
        // First-page bulk load of every row in parallel. Subsequent
        // pages use loadMore(row:) on demand from the UI.
        isLoadingDiscover = true
        errorMessage = nil
        defer { isLoadingDiscover = false }

        trending = PagedSection()
        popularMovies = PagedSection()
        popularTV = PagedSection()
        upcomingMovies = PagedSection()
        upcomingTV = PagedSection()

        do {
            async let trendingTask = discoverService.trending(page: 1)
            async let moviesTask = discoverService.popularMovies(page: 1)
            async let tvTask = discoverService.popularTV(page: 1)
            async let upcomingMoviesTask = discoverService.upcomingMovies(page: 1)
            async let upcomingTVTask = discoverService.upcomingTV(page: 1)

            let (t, m, tv, um, ut) = try await (
                trendingTask, moviesTask, tvTask,
                upcomingMoviesTask, upcomingTVTask
            )
            trending = PagedSection(items: t.results, currentPage: 1, totalPages: t.totalPages)
            popularMovies = PagedSection(items: m.results, currentPage: 1, totalPages: m.totalPages)
            popularTV = PagedSection(items: tv.results, currentPage: 1, totalPages: tv.totalPages)
            upcomingMovies = PagedSection(items: um.results, currentPage: 1, totalPages: um.totalPages)
            upcomingTV = PagedSection(items: ut.results, currentPage: 1, totalPages: ut.totalPages)
        } catch {
            errorMessage = error.localizedDescription
        }

        // Genre sliders + provider backdrops load best-effort in the
        // background — failures here just leave the rows looking
        // plain, they don't poison the whole discover screen.
        Task { await loadGenres() }
        Task { await loadProviderBackdrops() }
    }

    private func loadGenres() async {
        async let movieTask = try? discoverService.movieGenres()
        async let tvTask = try? discoverService.tvGenres()
        let (movie, tv) = await (movieTask, tvTask)
        if let movie { movieGenres = movie }
        if let tv { tvGenres = tv }
    }

    private func loadProviderBackdrops() async {
        // Fans out one fetch per provider/studio. Two jobs in one pass:
        //
        //  1. Pull a sample backdrop for the tile background — page 1
        //     with default sort gives "popular on this service first",
        //     good enough as a hero image.
        //
        //  2. Persist that first page to FilterCache under exactly
        //     the same key CatalogDiscoverView's empty-tile-hide
        //     filter checks (`streamingService-{id}-{region}`,
        //     `tvNetwork-{id}`, `movieStudio-{id}`). Without this the
        //     filter only kicks in *after* the user has tapped each
        //     tile once, so providers with no content in the user's
        //     region (Hulu / Peacock outside US, Hotstar outside
        //     India, …) keep showing as full tiles that tap into
        //     emptiness. Caching here means the very first render of
        //     the catalog already drops them.
        //
        // For streamers with a TMDB watch-provider id, we fetch movies
        // + tv in parallel and merge them — same shape the user gets
        // when tapping the tile, so the cache hit is exact and the
        // count is honest. Falls back to the TV-network endpoint for
        // broadcast-only entries (ABC, NBC, CBS).
        let region = Locale.current.region?.identifier ?? "US"
        let results = await withTaskGroup(
            of: ProviderResolveResult.self,
            returning: [ProviderResolveResult].self
        ) { group in
            for provider in CatalogProviders.networks {
                group.addTask { [discoverService] in
                    if let watchID = provider.tmdbWatchProviderID {
                        async let moviesTask = try? discoverService.moviesByWatchProvider(
                            providerID: watchID, region: region, page: 1
                        )
                        async let tvTask = try? discoverService.tvByWatchProvider(
                            providerID: watchID, region: region, page: 1
                        )
                        let (movies, tv) = await (moviesTask, tvTask)
                        let merged = (movies?.results ?? []) + (tv?.results ?? [])
                        let totalPages = max(movies?.totalPages ?? 0, tv?.totalPages ?? 0)
                        var backdrop = merged.first(where: { $0.backdropPath != nil })?.backdropPath
                        if backdrop == nil {
                            // Backdrop fallback: TV network endpoint
                            // sometimes carries different items.
                            let fallback = try? await discoverService.tvByNetwork(
                                networkID: provider.id, page: 1
                            )
                            backdrop = fallback?.results.first(where: { $0.backdropPath != nil })?.backdropPath
                        }
                        return ProviderResolveResult(
                            kind: .network,
                            displayID: provider.id,
                            cacheKey: FilterCacheKey.Catalog.streamingService(
                                watchProviderID: watchID, region: region
                            ),
                            items: merged,
                            totalPages: max(totalPages, 1),
                            backdrop: backdrop
                        )
                    } else {
                        let result = try? await discoverService.tvByNetwork(
                            networkID: provider.id, page: 1
                        )
                        return ProviderResolveResult(
                            kind: .network,
                            displayID: provider.id,
                            cacheKey: FilterCacheKey.Catalog.tvNetwork(id: provider.id),
                            items: result?.results ?? [],
                            totalPages: max(result?.totalPages ?? 1, 1),
                            backdrop: result?.results.first(where: { $0.backdropPath != nil })?.backdropPath
                        )
                    }
                }
            }
            for provider in CatalogProviders.studios {
                group.addTask { [discoverService] in
                    let result = try? await discoverService.moviesByStudio(
                        studioID: provider.id, page: 1
                    )
                    return ProviderResolveResult(
                        kind: .studio,
                        displayID: provider.id,
                        cacheKey: FilterCacheKey.Catalog.movieStudio(id: provider.id),
                        items: result?.results ?? [],
                        totalPages: max(result?.totalPages ?? 1, 1),
                        backdrop: result?.results.first(where: { $0.backdropPath != nil })?.backdropPath
                    )
                }
            }
            var collected: [ProviderResolveResult] = []
            for await item in group { collected.append(item) }
            return collected
        }

        // MainActor pass — write the cache + backdrop once everything's
        // resolved. Keeping the FilterCache writes off the detached
        // closures avoids the async-isolation error and centralises
        // the side effects in one easy-to-read sweep.
        for result in results {
            FilterCache.shared.setCatalogPage(
                result.items,
                totalPages: result.totalPages,
                filterKey: result.cacheKey
            )
            if let backdrop = result.backdrop {
                switch result.kind {
                case .network: networkBackdrops[result.displayID] = backdrop
                case .studio: studioBackdrops[result.displayID] = backdrop
                }
            }
        }
    }

    private struct ProviderResolveResult: Sendable {
        let kind: ProviderKind
        let displayID: Int
        let cacheKey: String
        let items: [SeerrMedia]
        let totalPages: Int
        let backdrop: String?
    }

    private enum ProviderKind { case network, studio }

    enum DiscoverRow {
        case trending, movies, tv, upcomingMovies, upcomingTV
    }

    /// Load the next page for a single row. Called by the horizontal row
    /// when the user scrolls close to the end. Dedupes against the current
    /// items — Seerr occasionally returns the same entry on adjacent pages
    /// when the trending list shifts.
    func loadMore(row: DiscoverRow) async {
        var section = section(for: row)
        guard !section.isLoading, section.hasMore else { return }

        section.isLoading = true
        updateSection(row, to: section)

        do {
            let nextPage = section.currentPage + 1
            let result: SeerrDiscoverResult
            switch row {
            case .trending:
                result = try await discoverService.trending(page: nextPage)
            case .movies:
                result = try await discoverService.popularMovies(page: nextPage)
            case .tv:
                result = try await discoverService.popularTV(page: nextPage)
            case .upcomingMovies:
                result = try await discoverService.upcomingMovies(page: nextPage)
            case .upcomingTV:
                result = try await discoverService.upcomingTV(page: nextPage)
            }

            let existingKeys = Set(section.items.map(\.stableKey))
            let additions = result.results.filter { !existingKeys.contains($0.stableKey) }

            section.items.append(contentsOf: additions)
            section.currentPage = result.page
            section.totalPages = result.totalPages
            section.isLoading = false
            updateSection(row, to: section)
        } catch {
            section.isLoading = false
            updateSection(row, to: section)
            // Swallow pagination errors — the user still has page 1 visible,
            // surfacing a banner mid-scroll would be jarring.
        }
    }

    func loadMyRequests(userID: Int) async {
        isLoadingRequests = true
        errorMessage = nil
        defer { isLoadingRequests = false }

        do {
            let result = try await requestService.myRequests(
                userID: userID,
                take: 50,
                skip: 0
            )
            myRequests = result.results
            // Kick off the enrichment in the background — the list
            // renders immediately with placeholder titles and swaps
            // to real metadata as each detail fetch returns.
            Task { await enrichRequestMetadata(for: result.results) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enrichRequestMetadata(for requests: [SeerrRequest]) async {
        // Deduplicate the tmdbIDs we haven't already enriched, then
        // fire all the detail fetches in parallel. Each row's view
        // body reads through requestMovieDetails / requestTVDetails
        // and updates when the corresponding entry lands.
        var movieIDs = Set<Int>()
        var tvIDs = Set<Int>()
        for request in requests {
            guard let tmdbID = request.media?.tmdbId else { continue }
            switch request.type {
            case .movie:
                if requestMovieDetails[tmdbID] == nil { movieIDs.insert(tmdbID) }
            case .tv:
                if requestTVDetails[tmdbID] == nil { tvIDs.insert(tmdbID) }
            case .person:
                break
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for id in movieIDs {
                group.addTask { [weak self] in
                    guard let detail = try? await self?.mediaService.movieDetail(tmdbID: id) else { return }
                    await MainActor.run {
                        self?.requestMovieDetails[id] = detail
                    }
                }
            }
            for id in tvIDs {
                group.addTask { [weak self] in
                    guard let detail = try? await self?.mediaService.tvDetail(tmdbID: id) else { return }
                    await MainActor.run {
                        self?.requestTVDetails[id] = detail
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func section(for row: DiscoverRow) -> PagedSection {
        switch row {
        case .trending: trending
        case .movies: popularMovies
        case .tv: popularTV
        case .upcomingMovies: upcomingMovies
        case .upcomingTV: upcomingTV
        }
    }

    private func updateSection(_ row: DiscoverRow, to new: PagedSection) {
        switch row {
        case .trending: trending = new
        case .movies: popularMovies = new
        case .tv: popularTV = new
        case .upcomingMovies: upcomingMovies = new
        case .upcomingTV: upcomingTV = new
        }
    }
}
