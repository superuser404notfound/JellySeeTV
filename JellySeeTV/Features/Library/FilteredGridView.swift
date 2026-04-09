import SwiftUI

struct FilteredGridView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var items: [JellyfinItem] = []
    @State private var isLoading = true
    @State private var selectedItem: JellyfinItem?
    @Environment(\.dismiss) private var dismiss

    let title: String
    let query: ItemQuery

    var body: some View {
        ScrollView {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 60)
                .padding(.top, 20)

            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    // Focusable element so Menu button works during loading
                    Button("") { dismiss() }
                        .opacity(0)
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("home.retry")
                        .foregroundStyle(.secondary)
                    Button { dismiss() } label: {
                        Text("detail.showSeries")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 220), spacing: 40)
                ], spacing: 50) {
                    ForEach(items) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            MediaCard(
                                item: item,
                                imageURL: dependencies.jellyfinImageService.posterURL(for: item)
                            )
                        }
                        .buttonStyle(GridCardButtonStyle())
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
        }
        .navigationBarHidden(true)
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

struct GridCardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 20, y: 10)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
