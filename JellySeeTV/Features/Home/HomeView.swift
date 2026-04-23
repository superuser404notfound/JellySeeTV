import SwiftUI

struct HomeView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: HomeViewModel?
    @State private var selectedItem: JellyfinItem?
    @State private var selectedFilter: FilterDestination?

    /// How long the home feed is considered fresh before a revisit
    /// triggers an automatic reload.
    private static let refreshStaleSeconds: TimeInterval = 60

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = vm.errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text(error)
                                .foregroundStyle(.secondary)
                            Button("home.retry") {
                                Task { await vm.loadContent() }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        contentView(vm: vm)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationDestination(item: $selectedItem) { item in
                DetailRouterView(item: item)
            }
            .navigationDestination(item: $selectedFilter) { filter in
                FilteredGridView(title: filter.title, query: filter.query)
            }
        }
        .onAppear {
            guard let userID = appState.activeUser?.id else { return }
            if viewModel == nil {
                viewModel = HomeViewModel(
                    libraryService: dependencies.jellyfinLibraryService,
                    imageService: dependencies.jellyfinImageService,
                    userID: userID
                )
                Task { await viewModel?.loadContent() }
            } else if viewModel?.needsReload == true {
                viewModel?.needsReload = false
                Task { await viewModel?.loadContent() }
            } else if let last = viewModel?.lastLoadedAt,
                      Date().timeIntervalSince(last) > Self.refreshStaleSeconds {
                // Pick up new server-side content (Latest Movies,
                // Latest Series, …) when the user comes back to Home
                // after a while. 60 s is tight enough that fresh
                // additions show up quickly and loose enough that
                // rapid tab-hopping doesn't spam the server.
                Task { await viewModel?.loadContent() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeConfigDidChange)) { _ in
            viewModel?.reloadConfig()
            viewModel?.needsReload = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .homeFavoritesDidChange)) { _ in
            Task { await viewModel?.loadContent() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playbackProgressDidChange)) { _ in
            // The Jellyfin server has fresh progress for whatever
            // the user just watched. Reload so Continue Watching and
            // Next Up reflect it as soon as the user is back here.
            Task { await viewModel?.loadContent() }
        }
    }

    private func contentView(vm: HomeViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 40) {
                ForEach(vm.orderedSections()) { section in
                    switch section {
                    case .media(let row):
                        HorizontalMediaRow(
                            title: row.type.localizedTitle,
                            items: row.items,
                            imageURLProvider: { vm.imageURL(for: $0, rowType: row.type) },
                            onItemSelected: { selectedItem = $0 },
                            cardStyle: row.type.cardStyle
                        )

                    case .tags(let tagRow):
                        TagRow(
                            title: tagRow.type.localizedTitle,
                            tags: tagRow.tags,
                            onTagSelected: { tagData in
                                selectedFilter = makeFilter(for: tagData, type: tagRow.type)
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 40)
        }
    }

    private func makeFilter(for tag: TagCardData, type: HomeRowType) -> FilterDestination {
        switch type {
        case .genres:
            FilterDestination(
                title: tag.name,
                query: ItemQuery(
                    includeItemTypes: [.movie, .series],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 50,
                    genres: [tag.name]
                )
            )
        case .studios:
            FilterDestination(
                title: tag.name,
                query: ItemQuery(
                    includeItemTypes: [.movie, .series],
                    sortBy: "SortName",
                    sortOrder: "Ascending",
                    limit: 50,
                    studioNames: [tag.name]
                )
            )
        default:
            FilterDestination(title: tag.name, query: ItemQuery())
        }
    }
}

struct FilterDestination: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let query: ItemQuery
}

extension ItemQuery: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(parentID)
        hasher.combine(sortBy)
        hasher.combine(genres)
        hasher.combine(studioNames)
    }

    static func == (lhs: ItemQuery, rhs: ItemQuery) -> Bool {
        lhs.parentID == rhs.parentID &&
        lhs.sortBy == rhs.sortBy &&
        lhs.genres == rhs.genres &&
        lhs.studioNames == rhs.studioNames &&
        lhs.isFavorite == rhs.isFavorite
    }
}
