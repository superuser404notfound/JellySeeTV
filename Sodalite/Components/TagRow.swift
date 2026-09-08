import SwiftUI

struct TagRow: View {
    let title: LocalizedStringKey
    let tags: [TagCardData]
    var onTagSelected: ((TagCardData) -> Void)?

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var metrics: LayoutMetrics { LayoutMetrics.current(hSizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, metrics.rowInset)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: metrics.itemSpacing) {
                    ForEach(tags) { tag in
                        GenreCard(data: tag) {
                            onTagSelected?(tag)
                        }
                    }
                }
                .padding(.horizontal, metrics.rowInset)
                .padding(.vertical, metrics.rowVerticalPadding)
            }
            .focusSectionCompat()
        }
    }
}

struct TagCardData: Identifiable, Sendable {
    let id: String
    let name: String
    let backdropURL: URL?
}

struct GenreCard: View {
    let data: TagCardData
    let action: () -> Void

    @Environment(\.dependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        ArtworkTile(
            title: data.name,
            artworkURL: data.backdropURL,
            size: LayoutMetrics.current(hSizeClass)
                .tileSize(cardScale: dependencies.appearancePreferences.cardScale),
            action: action
        ) {
            ArtworkTileSurface()
        }
    }
}
