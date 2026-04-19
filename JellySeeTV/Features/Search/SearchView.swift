import SwiftUI

struct SearchView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: SearchViewModel?
    @State private var selectedJellyfinItem: JellyfinItem?
    @State private var selectedSeerrMedia: SeerrMedia?

    var body: some View {
        NavigationStack {
            Group {
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
            // Apple's native tvOS search affordance. On tvOS 17+ this
            // renders in the navigation bar area above the content and
            // is owned by the system focus engine — no custom overlays,
            // no focus hacks, no geometric routing surprises. The
            // keyboard appears the moment the system bar receives focus
            // (tab bar → search bar → content, reliably in both
            // directions), and the system handles tab-switch state for
            // us so we don't need the restore-focus dance on pop-back.
            .searchable(
                text: searchQueryBinding,
                prompt: Text("search.placeholder")
            )
            .navigationDestination(item: $selectedJellyfinItem) { item in
                DetailRouterView(item: item)
            }
            .navigationDestination(item: $selectedSeerrMedia) { media in
                CatalogDetailView(media: media)
            }
        }
        .onAppear(perform: bootstrap)
    }

    /// Binding that proxies the view model's query through .searchable
    /// — keeps the view model as the single source of truth (so other
    /// views/VMs can read/react to it) while giving the system bar the
    /// `Binding<String>` it expects.
    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { viewModel?.query ?? "" },
            set: { newValue in
                guard let vm = viewModel else { return }
                vm.query = newValue
                vm.scheduleSearch()
            }
        )
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

