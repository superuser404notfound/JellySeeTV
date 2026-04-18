import SwiftUI

struct SearchView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: SearchViewModel?
    @State private var selectedJellyfinItem: JellyfinItem?
    @State private var selectedSeerrMedia: SeerrMedia?
    @State private var showInputSheet = false
    @FocusState private var searchBarFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if let vm = viewModel {
                    if vm.jellyfinResults.isEmpty && vm.seerrResults.isEmpty {
                        emptyState(vm: vm)
                    } else {
                        resultsView(vm: vm)
                    }
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
        .sheet(isPresented: $showInputSheet) {
            if let vm = viewModel {
                SearchInputSheet(query: Bindable(vm).query) {
                    vm.scheduleSearch()
                }
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

    /// After the user pops back from a detail view, make the search bar
    /// button regain focus so a Menu press pops the tab bar instead of
    /// exiting the app (see MovieDetailView's playButtonFocused for the
    /// same pattern).
    private func restoreSearchFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            searchBarFocused = true
        }
    }

    /// The search bar is a Button (not a TextField) because tvOS's focus
    /// engine routes buttons reliably along the vertical axis between
    /// the tab bar and the result cards — TextField is technically
    /// focusable but the engine skips over it and lands on whichever
    /// card or tab is geometrically next. Tapping the button opens a
    /// modal sheet with the actual text input, which is the same
    /// pattern Apple Music and the App Store search use on tvOS.
    private var searchBar: some View {
        Button {
            showInputSheet = true
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(searchBarLabel)
                    .foregroundStyle(searchBarLabelIsPlaceholder ? .secondary : .primary)
                Spacer()
                if viewModel?.isSearching == true {
                    ProgressView()
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(searchBarFocused ? 0.15 : 0.08))
            )
            .scaleEffect(searchBarFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: searchBarFocused)
        }
        .buttonStyle(.plain)
        .focused($searchBarFocused)
        .padding(.horizontal, 80)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }

    private var searchBarLabel: String {
        if let q = viewModel?.query.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            return q
        }
        return String(localized: "search.placeholder", defaultValue: "Search")
    }

    private var searchBarLabelIsPlaceholder: Bool {
        (viewModel?.query.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
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

/// Modal sheet with the actual text field. Presented from the search
/// bar button so tvOS can run its native text-input UI (keyboard
/// overlay on tvOS, full keyboard on iOS) without us fighting the
/// main-screen focus engine. The sheet closes itself on Menu or when
/// the user dismisses the keyboard; query changes are debounced by
/// the view model via `onQueryChange`.
struct SearchInputSheet: View {
    @Binding var query: String
    let onQueryChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 40) {
            Text("search.placeholder")
                .font(.title2)
                .fontWeight(.semibold)

            TextField(
                String(localized: "search.placeholder", defaultValue: "Search"),
                text: $query
            )
            .autocorrectionDisabled()
            .focused($fieldFocused)
            .frame(maxWidth: 800)
            .onChange(of: query) { _, _ in
                onQueryChange()
            }

            Button {
                dismiss()
            } label: {
                Text("common.back")
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
        .onAppear {
            fieldFocused = true
        }
    }
}
