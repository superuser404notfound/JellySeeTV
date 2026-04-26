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
            // Reset state when navigating to a different filter
            // (rare on tvOS, but keeps the view robust if the same
            // navigationDestination instance is reused).
            items = []
            page = 0
            totalPages = 1
            errorMessage = nil
            await loadMore()
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

    private func loadMore() async {
        guard !isLoadingMore, page < totalPages else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = page + 1
        do {
            let result: SeerrDiscoverResult
            switch filter {
            case .movieGenre(let id, _):
                result = try await dependencies.seerrDiscoverService
                    .moviesByGenre(genreID: id, page: nextPage)
            case .tvGenre(let id, _):
                result = try await dependencies.seerrDiscoverService
                    .tvByGenre(genreID: id, page: nextPage)
            case .movieStudio(let id, _):
                result = try await dependencies.seerrDiscoverService
                    .moviesByStudio(studioID: id, page: nextPage)
            case .tvNetwork(let id, _):
                result = try await dependencies.seerrDiscoverService
                    .tvByNetwork(networkID: id, page: nextPage)
            case .streamingService(let providerID, _, let region):
                // Fetch movies and TV in parallel from the watch-
                // providers endpoint, merge results. Both endpoints
                // independently paginate; we mirror the slowest of
                // the two as the page/totalPages so neither side
                // gets cut off prematurely.
                async let moviesTask = dependencies.seerrDiscoverService
                    .moviesByWatchProvider(providerID: providerID, region: region, page: nextPage)
                async let tvTask = dependencies.seerrDiscoverService
                    .tvByWatchProvider(providerID: providerID, region: region, page: nextPage)
                let (movies, tv) = try await (moviesTask, tvTask)
                result = SeerrDiscoverResult(
                    page: nextPage,
                    totalPages: max(movies.totalPages, tv.totalPages),
                    totalResults: movies.totalResults + tv.totalResults,
                    results: movies.results + tv.results
                )
            }

            let existing = Set(items.map(\.stableKey))
            let additions = result.results.filter { !existing.contains($0.stableKey) }
            items.append(contentsOf: additions)
            page = result.page
            totalPages = result.totalPages
        } catch {
            errorMessage = error.localizedDescription
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
