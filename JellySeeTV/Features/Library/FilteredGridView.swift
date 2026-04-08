import SwiftUI

struct FilteredGridView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var items: [JellyfinItem] = []
    @State private var isLoading = true
    @State private var selectedItem: JellyfinItem?

    let title: String
    let query: ItemQuery

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("home.retry")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 180), spacing: 24)
                ], spacing: 30) {
                    ForEach(items) { item in
                        FocusableCard {
                            selectedItem = item
                        } content: { _ in
                            MediaCard(
                                item: item,
                                imageURL: dependencies.jellyfinImageService.posterURL(for: item)
                            )
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
        .navigationTitle(title)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedItem) { item in
            DetailRouterView(item: item)
        }
        .task {
            await loadItems()
        }
    }

    private func loadItems() async {
        guard let userID = appState.activeUser?.id else { return }
        isLoading = true
        do {
            let response = try await dependencies.jellyfinLibraryService.getItems(
                userID: userID,
                query: query
            )
            items = response.items
        } catch {
            // Show empty state
        }
        isLoading = false
    }
}
