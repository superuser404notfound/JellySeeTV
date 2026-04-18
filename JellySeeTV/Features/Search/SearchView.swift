import SwiftUI

struct SearchView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: SearchViewModel?
    @State private var selectedJellyfinItem: JellyfinItem?
    @State private var selectedSeerrMedia: SeerrMedia?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Wrapping the search bar in its own focus section makes
                // the tvOS focus engine treat "coming down from the tab
                // bar" as entering the search-bar section first — the
                // text field grabs focus before any result card. Results
                // get their own section so horizontal navigation between
                // cards still works naturally once the user steps down.
                searchBar
                    .focusSection()

                if let vm = viewModel {
                    Group {
                        if vm.jellyfinResults.isEmpty && vm.seerrResults.isEmpty {
                            emptyState(vm: vm)
                        } else {
                            resultsView(vm: vm)
                        }
                    }
                    .focusSection()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationDestination(item: $selectedJellyfinItem) { item in
                DetailRouterView(item: item)
            }
            .navigationDestination(item: $selectedSeerrMedia) { media in
                CatalogDetailView(media: media)
            }
        }
        .onAppear(perform: bootstrap)
        .onChange(of: selectedJellyfinItem) { _, newValue in
            if newValue == nil { restoreSearchFocus() }
        }
        .onChange(of: selectedSeerrMedia) { _, newValue in
            if newValue == nil { restoreSearchFocus() }
        }
    }

    /// After the user pops back from a detail view, tvOS sometimes leaves
    /// the system in a brief window with no focused element — if the Menu
    /// button fires during that gap it routes all the way up to App-Exit
    /// instead of popping the tab-bar level. Re-focusing the search field
    /// right after the pop closes that gap. Same pattern MovieDetailView
    /// uses for its play button (playButtonFocused).
    private func restoreSearchFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            searchFieldFocused = true
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            if let vm = viewModel {
                TextField(
                    String(localized: "search.placeholder", defaultValue: "Search"),
                    text: Bindable(vm).query
                )
                .autocorrectionDisabled()
                .focused($searchFieldFocused)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of: vm.query) { _, _ in
                    vm.scheduleSearch()
                }
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func resultsView(vm: SearchViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 40) {
                if !vm.jellyfinResults.isEmpty {
                    librarySection(items: vm.jellyfinResults)
                }
                if !vm.seerrResults.isEmpty {
                    catalogSection(items: vm.seerrResults)
                }
                if vm.isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 40)
                }
            }
            .padding(.vertical, 20)
        }
    }

    private func librarySection(items: [JellyfinItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "house.fill", title: "search.section.library", tint: .accentColor)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 30) {
                    ForEach(items) { item in
                        FocusableCard {
                            selectedJellyfinItem = item
                        } content: { _ in
                            MediaCard(
                                item: item,
                                imageURL: dependencies.jellyfinImageService.imageURL(
                                    itemID: item.id,
                                    imageType: .primary,
                                    tag: item.imageTags?.primary,
                                    maxWidth: 440
                                ),
                                style: .poster
                            )
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }

    private func catalogSection(items: [SeerrMedia]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "tray.and.arrow.down", title: "search.section.catalog", tint: .orange)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 30) {
                    ForEach(items) { media in
                        FocusableCard {
                            selectedSeerrMedia = media
                        } content: { _ in
                            SeerrMediaCard(media: media)
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }

    private func sectionHeader(icon: String, title: LocalizedStringKey, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func emptyState(vm: SearchViewModel) -> some View {
        if vm.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.query.trimmingCharacters(in: .whitespaces).count < 2 {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("search.hint.startTyping")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if !appState.isSeerrConnected {
                    Text("search.hint.connectSeerr")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("search.empty.noResults")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func bootstrap() {
        guard viewModel == nil, let userID = appState.activeUser?.id else { return }
        viewModel = SearchViewModel(
            itemService: dependencies.jellyfinItemService,
            seerrSearchService: appState.isSeerrConnected ? dependencies.seerrSearchService : nil,
            userID: userID
        )
    }
}
