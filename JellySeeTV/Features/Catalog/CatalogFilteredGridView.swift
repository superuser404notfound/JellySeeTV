import SwiftUI

/// Paged grid of SeerrMedia for a single CatalogFilter
/// (genre, network, studio). Mirrors the discover-row pagination
/// pattern but in a vertical grid so the user can browse the full
/// catalogue for that filter, not just the first row's worth.
struct CatalogFilteredGridView: View {
    let filter: CatalogFilter

    @Environment(\.dependencies) private var dependencies

    @State private var items: [SeerrMedia] = []
    @State private var page: Int = 0
    @State private var totalPages: Int = 1
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var selectedMedia: SeerrMedia?

    private let columns: [GridItem] = Array(
        repeating: GridItem(.fixed(220), spacing: 32),
        count: 6
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(filter.displayName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal, 80)
                    .padding(.top, 40)

                if items.isEmpty && isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 400)
                } else if let errorMessage, items.isEmpty {
                    errorState(message: errorMessage)
                } else {
                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(items) { media in
                            FocusableCard(
                                action: { selectedMedia = media }
                            ) { focused in
                                SeerrMediaCard(media: media, isFocused: focused)
                            }
                            .id(media.stableKey)
                            .onAppear {
                                if shouldPaginate(after: media) {
                                    Task { await loadMore() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 16)

                    if isLoadingMore && !items.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedMedia) { media in
            CatalogDetailView(media: media)
        }
        .task(id: filter) {
            errorMessage = nil

            // Stale-while-revalidate: hydrate from cache synchronously
            // so the grid appears in the same render pass — actor
            // suspensions used to insert a frame of empty state in
            // between, which read as a 1-2 second flicker before the
            // refresh landed. FilterCache is a plain class now;
            // reads can happen from inside a task body without an
            // await hop.
            if let cached = FilterCache.shared.catalogPage(filterKey: filter.cacheKey) {
                items = cached.items
                page = 1
                totalPages = cached.totalPages
            } else {
                items = []
                page = 0
                totalPages = 1
            }
            await refreshFirstPage()
        }
    }

    // MARK: - Pagination

    private func shouldPaginate(after media: SeerrMedia) -> Bool {
        guard !isLoadingMore, page < totalPages else { return false }
        // Trigger when the user scrolls within ~12 items of the end —
        // gives the network call time to land before they hit the
        // bottom of the visible grid.
        let key = media.stableKey
        guard let index = items.firstIndex(where: { $0.stableKey == key }) else {
            return false
        }
        return index >= items.count - 12
    }

    /// Always re-fetches page 1 and replaces the displayed items
    /// wholesale — used on view appearance to pick up any rotation
    /// in the provider's lineup since last visit. Updates the cache
    /// so the next appearance hydrates instantly. Subsequent pages
    /// (2+) still go through `loadMore` on demand.
    private func refreshFirstPage() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await fetchPage(1)
            items = result.results
            page = 1
            totalPages = result.totalPages
            errorMessage = nil
            FilterCache.shared.setCatalogPage(
                result.results,
                totalPages: result.totalPages,
                filterKey: filter.cacheKey
            )
        } catch {
            // Keep whatever the cache hydrated us with rather than
            // wiping the screen on a transient network blip.
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, page < totalPages else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = page + 1
        do {
            let result = try await fetchPage(nextPage)
            let existing = Set(items.map(\.stableKey))
            let additions = result.results.filter { !existing.contains($0.stableKey) }
            items.append(contentsOf: additions)
            page = result.page
            totalPages = result.totalPages
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Dispatches to the right discover endpoint(s) for the active
    /// filter, returning a single `SeerrDiscoverResult`. The
    /// streaming-service case fans out movies + tv in parallel and
    /// merges; everything else is a single endpoint.
    private func fetchPage(_ page: Int) async throws -> SeerrDiscoverResult {
        switch filter {
        case .movieGenre(let id, _):
            return try await dependencies.seerrDiscoverService
                .moviesByGenre(genreID: id, page: page)
        case .tvGenre(let id, _):
            return try await dependencies.seerrDiscoverService
                .tvByGenre(genreID: id, page: page)
        case .movieStudio(let id, _):
            return try await dependencies.seerrDiscoverService
                .moviesByStudio(studioID: id, page: page)
        case .tvNetwork(let id, _):
            return try await dependencies.seerrDiscoverService
                .tvByNetwork(networkID: id, page: page)
        case .streamingService(let providerID, _, let region):
            async let moviesTask = dependencies.seerrDiscoverService
                .moviesByWatchProvider(providerID: providerID, region: region, page: page)
            async let tvTask = dependencies.seerrDiscoverService
                .tvByWatchProvider(providerID: providerID, region: region, page: page)
            let (movies, tv) = try await (moviesTask, tvTask)
            return SeerrDiscoverResult(
                page: page,
                totalPages: max(movies.totalPages, tv.totalPages),
                totalResults: movies.totalResults + tv.totalResults,
                results: movies.results + tv.results
            )
        }
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}
