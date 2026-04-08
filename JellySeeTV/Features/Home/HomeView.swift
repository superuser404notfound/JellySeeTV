import SwiftUI

struct HomeView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: HomeViewModel?
    @State private var selectedItem: JellyfinItem?
    @State private var showCustomize = false

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
            guard let userID = appState.activeUser?.id else { return }
            if viewModel == nil {
                viewModel = HomeViewModel(
                    libraryService: dependencies.jellyfinLibraryService,
                    imageService: dependencies.jellyfinImageService,
                    userID: userID
                )
                Task { await viewModel?.loadContent() }
            } else {
                // Reload config in case it changed in settings
                let oldConfigs = viewModel?.rowConfigs
                viewModel?.reloadConfig()
                if viewModel?.rowConfigs != oldConfigs {
                    Task { await viewModel?.loadContent() }
                }
            }
        }
    }

    private func contentView(vm: HomeViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 40) {
                ForEach(vm.rows) { row in
                    HorizontalMediaRow(
                        title: row.type.localizedTitle,
                        items: row.items,
                        imageURLProvider: { vm.imageURL(for: $0, rowType: row.type) },
                        onItemSelected: { selectedItem = $0 },
                        cardStyle: row.type.cardStyle
                    )
                }
            }
            .padding(.vertical, 40)
        }
    }
}
