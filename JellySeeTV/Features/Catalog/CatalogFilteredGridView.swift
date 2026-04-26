import SwiftUI

/// Paged grid of SeerrMedia for a single CatalogFilter
/// (genre, network, studio). Mirrors the discover-row pagination
/// pattern but in a vertical grid so the user can browse the full
/// catalogue for that filter, not just the first row's worth.
struct CatalogFilteredGridView: View {
    let filter: CatalogFilter

    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var items: [SeerrMedia]
    @State private var page: Int
    @State private var totalPages: Int
    @State private var isLoadingMore = false
    /// Background revalidation flag — true while we're re-fetching
    /// page 1 to refresh the cached grid. Deliberately separate from
    /// `isLoadingMore` so we *don't* paint a spinner during silent
    /// stale-while-revalidate. The user already sees the cached grid;
    /// surfacing a "loading" hint for a refresh they didn't trigger
    /// reads as a real network roundtrip even when it isn't.
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var selectedMedia: SeerrMedia?

    private let columns: [GridItem] = Array(
        repeating: GridItem(.fixed(220), spacing: 32),
        count: 6
    )

    init(filter: CatalogFilter) {
        self.filter = filter
        // Hydrate from FilterCache *during init* so the very first
        // body render already paints the cached grid. Doing it inside
        // `.task(id:)` later would mean one frame of empty state
        // before the cache snaps in — visible as a tiny "loading"
        // flash on every tap that the user perceives as a network
        // round-trip even when the answer is already on disk.
        if let cached = FilterCache.shared.catalogPage(filterKey: filter.cacheKey) {
            _items = State(initialValue: cached.items)
            _page = State(initialValue: 1)
            _totalPages = State(initialValue: cached.totalPages)
        } else {
            _items = State(initialValue: [])
            _page = State(initialValue: 0)
            _totalPages = State(initialValue: 1)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(filter.displayName)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal, 80)
                    .padding(.top, 40)

                if items.isEmpty && (isLoadingMore || isRefreshing) {
                    loadingState
                } else if let errorMessage, items.isEmpty {
                    errorState(message: errorMessage)
                } else if items.isEmpty {
                    emptyState
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
            // Initial hydration happened in init(filter:) so the grid
            // is already on screen by the time we get here. All this
            // task has to do is fire the background refresh that
            // replaces the cached items with the freshest page 1 from
            // Jellyseerr.
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
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await fetchPage(1)
            // Only replace items if the result actually changed —
            // wholesale `items = result.results` even with identical
            // IDs forces SwiftUI to re-evaluate every cell, which the
            // user reads as a "reload flash" right after the cached
            // grid first paints. Comparing stableKeys keeps the view
            // tree untouched on the common case where nothing rotated
            // since last visit.
            let oldKeys = items.map(\.stableKey)
            let newKeys = result.results.map(\.stableKey)
            if oldKeys != newKeys {
                items = result.results
            }
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
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            // Without this Button the empty/error state has no
            // focusable element, so the Menu button on the Siri
            // Remote escapes the navigation stack and quits the app
            // instead of popping back to the catalog.
            Button { dismiss() } label: {
                Text("common.back")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    /// Shown when the filter genuinely has zero matches (e.g. a
    /// streaming-service tile whose region currently has no titles
    /// in the local discover endpoints). Same focusable back-button
    /// pattern as `errorState` so Menu pops back instead of quitting.
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("search.empty.noResults")
                .foregroundStyle(.secondary)
            Button { dismiss() } label: {
                Text("common.back")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    /// Loading state with an invisible focusable button so the Menu
    /// remote button still has somewhere to land — without it, a tap
    /// during the initial network roundtrip would quit the app.
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
            Button("") { dismiss() }
                .opacity(0)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}
