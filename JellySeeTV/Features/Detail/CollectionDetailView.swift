import SwiftUI

struct CollectionDetailView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: DetailViewModel?
    @State private var selectedItem: JellyfinItem?
    @State private var showPlayer = false

    let item: JellyfinItem

    var body: some View {
        Group {
            if let vm = viewModel {
                contentView(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .navigationDestination(item: $selectedItem) { item in
            DetailRouterView(item: item)
        }
        .onAppear {
            if viewModel == nil, let userID = appState.activeUser?.id {
                viewModel = DetailViewModel(
                    item: item,
                    itemService: dependencies.jellyfinItemService,
                    imageService: dependencies.jellyfinImageService,
                    userID: userID
                )
                Task {
                    await viewModel?.loadFullDetail()
                    await viewModel?.loadCollectionItems()
                }
            }
        }
    }

    private func contentView(vm: DetailViewModel) -> some View {
        ZStack {
            DetailBackdrop(imageURL: vm.backdropURL(for: vm.item))

            DetailContentOverlay {
                glassPanel(vm: vm)
                    .padding(.horizontal, 50)

                if let overview = vm.item.overview, !overview.isEmpty {
                    ExpandableTextBox(text: overview)
                        .padding(.horizontal, 50)
                }

                if !vm.collectionItems.isEmpty {
                    collectionList(vm: vm)
                }
            }
        }
    }

    // MARK: - Glass Panel

    private func glassPanel(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(vm.item.name)
                .font(.largeTitle)
                .fontWeight(.bold)

            if !vm.collectionItems.isEmpty {
                Text("detail.collection.itemCount \(vm.collectionItems.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                GlassActionButton(
                    title: "detail.play",
                    systemImage: "play.fill",
                    isProminent: true,
                    action: {
                        if let first = vm.collectionItems.first {
                            selectedItem = first
                        }
                    }
                )

                GlassActionButton(
                    title: vm.isFavorite ? "detail.unfavorite" : "detail.favorite",
                    systemImage: vm.isFavorite ? "heart.fill" : "heart",
                    action: { Task { await vm.toggleFavorite() } }
                )
            }
            .padding(.top, 4)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Collection Items (vertical list)

    private func collectionList(vm: DetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("detail.collection.items")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            VStack(spacing: 12) {
                ForEach(vm.collectionItems) { movie in
                    CollectionItemRow(
                        item: movie,
                        imageURL: dependencies.jellyfinImageService.posterURL(for: movie),
                        onSelect: { selectedItem = movie }
                    )
                }
            }
            .padding(.horizontal, 50)
        }
    }
}

// MARK: - Collection Item Row

struct CollectionItemRow: View {
    let item: JellyfinItem
    let imageURL: URL?
    let onSelect: () -> Void

    var body: some View {
        Button { onSelect() } label: {
            HStack(spacing: 20) {
                // Poster
                AsyncCachedImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.Theme.surface)
                }
                .frame(width: 80, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        if let year = item.productionYear {
                            Text(String(year))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let runtime = item.runTimeTicks {
                            Text(runtime.ticksToDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let score = item.communityRating {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption2)
                                Text(String(format: "%.1f", score))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let overview = item.overview {
                        Text(overview)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Play state
                if item.userData?.played == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let pct = item.userData?.playedPercentage, pct > 0 {
                    Text("\(Int(pct))%")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .padding(16)
        }
        .buttonStyle(CollectionRowButtonStyle())
    }
}

struct CollectionRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? .white.opacity(0.12) : .white.opacity(0.05))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
