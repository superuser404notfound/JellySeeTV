import SwiftUI

struct HomeView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: HomeViewModel?
    @State private var selectedItem: JellyfinItem?

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
        }
        .onAppear {
            if viewModel == nil, let userID = appState.activeUser?.id {
                viewModel = HomeViewModel(
                    libraryService: dependencies.jellyfinLibraryService,
                    imageService: dependencies.jellyfinImageService,
                    userID: userID
                )
                Task { await viewModel?.loadContent() }
            }
        }
    }

    private func contentView(vm: HomeViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 40) {
                if !vm.continueWatching.isEmpty {
                    HorizontalMediaRow(
                        title: "home.continueWatching",
                        items: vm.continueWatching,
                        imageURLProvider: { vm.posterURL(for: $0) },
                        onItemSelected: { selectedItem = $0 }
                    )
                }

                if !vm.nextUp.isEmpty {
                    HorizontalMediaRow(
                        title: "home.nextUp",
                        items: vm.nextUp,
                        imageURLProvider: { vm.posterURL(for: $0) },
                        onItemSelected: { selectedItem = $0 }
                    )
                }

                if !vm.latestMovies.isEmpty {
                    HorizontalMediaRow(
                        title: "home.latestMovies",
                        items: vm.latestMovies,
                        imageURLProvider: { vm.posterURL(for: $0) },
                        onItemSelected: { selectedItem = $0 }
                    )
                }

                if !vm.latestShows.isEmpty {
                    HorizontalMediaRow(
                        title: "home.latestShows",
                        items: vm.latestShows,
                        imageURLProvider: { vm.posterURL(for: $0) },
                        onItemSelected: { selectedItem = $0 }
                    )
                }
            }
            .padding(.vertical, 40)
        }
    }
}
