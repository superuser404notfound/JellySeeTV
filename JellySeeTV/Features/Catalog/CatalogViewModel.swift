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
    var myRequests: [SeerrRequest] = []

    var isLoadingDiscover = false
    var isLoadingRequests = false
    var errorMessage: String?

    private let discoverService: SeerrDiscoverServiceProtocol
    private let requestService: SeerrRequestServiceProtocol

    init(
        discoverService: SeerrDiscoverServiceProtocol,
        requestService: SeerrRequestServiceProtocol
    ) {
        self.discoverService = discoverService
        self.requestService = requestService
    }

    func loadDiscover() async {
        // First-page bulk load of all three rows in parallel. Subsequent
        // pages use loadMore(section:) on demand from the UI.
        isLoadingDiscover = true
        errorMessage = nil
        defer { isLoadingDiscover = false }

        trending = PagedSection()
        popularMovies = PagedSection()
        popularTV = PagedSection()

        do {
            async let trendingTask = discoverService.trending(page: 1)
            async let moviesTask = discoverService.popularMovies(page: 1)
            async let tvTask = discoverService.popularTV(page: 1)

            let (t, m, tv) = try await (trendingTask, moviesTask, tvTask)
            trending = PagedSection(items: t.results, currentPage: 1, totalPages: t.totalPages)
            popularMovies = PagedSection(items: m.results, currentPage: 1, totalPages: m.totalPages)
            popularTV = PagedSection(items: tv.results, currentPage: 1, totalPages: tv.totalPages)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    enum DiscoverRow {
        case trending, movies, tv
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
            }

            let existingKeys = Set(section.items.map { key(for: $0) })
            let additions = result.results.filter { !existingKeys.contains(key(for: $0)) }

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

    func loadMyRequests() async {
        isLoadingRequests = true
        errorMessage = nil
        defer { isLoadingRequests = false }

        do {
            let result = try await requestService.myRequests(take: 50, skip: 0)
            myRequests = result.results
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func key(for media: SeerrMedia) -> String {
        "\(media.mediaType.rawValue)-\(media.id)"
    }

    private func section(for row: DiscoverRow) -> PagedSection {
        switch row {
        case .trending: trending
        case .movies: popularMovies
        case .tv: popularTV
        }
    }

    private func updateSection(_ row: DiscoverRow, to new: PagedSection) {
        switch row {
        case .trending: trending = new
        case .movies: popularMovies = new
        case .tv: popularTV = new
        }
    }
}
