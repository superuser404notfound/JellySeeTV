import SwiftUI

/// Horizontal scroller of genre tiles (dimmed backdrop + name overlay); tap navigates to a CatalogFilteredGridView. The tile is the app-wide ArtworkTile rather than Jellyseerr web's centered label, so Catalog and Home read as one design (Sodalite#84).
struct CatalogGenreRow: View {
    let titleKey: LocalizedStringKey
    let genres: [SeerrGenreSlide]
    let kind: Kind
    let onSelect: (CatalogFilter) -> Void

    enum Kind { case movie, tv }

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var metrics: LayoutMetrics { LayoutMetrics.current(hSizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleKey)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, metrics.rowInset)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: metrics.itemSpacing) {
                    ForEach(genres) { genre in
                        GenreTile(genre: genre) {
                            onSelect(filter(for: genre))
                        }
                    }
                }
                .padding(.horizontal, metrics.rowInset)
                // Match SeerrHorizontalMediaRow vertical padding so the focus halo doesn't clip adjacent rows.
                .padding(.vertical, metrics.rowVerticalPadding)
            }
            .focusSectionCompat()
        }
    }

    private func filter(for genre: SeerrGenreSlide) -> CatalogFilter {
        switch kind {
        case .movie: .movieGenre(id: genre.id, name: genre.name)
        case .tv: .tvGenre(id: genre.id, name: genre.name)
        }
    }
}

private struct GenreTile: View {
    let genre: SeerrGenreSlide
    let action: () -> Void

    @Environment(\.dependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        ArtworkTile(
            title: genre.name,
            artworkURL: genre.primaryBackdrop.flatMap { SeerrImageURL.backdrop(path: $0, size: .covering(ImageWidth.wideCard)) },
            size: LayoutMetrics.current(hSizeClass)
                .tileSize(cardScale: dependencies.appearancePreferences.cardScale),
            action: action
        ) {
            fallbackBackground
        }
    }

    private var fallbackBackground: some View {
        // LinearGradient(colors:) needs concrete Colors, so resolve the effective control-role palette here.
        let tint = dependencies.appearancePreferences.resolvedTheme(
            isSupporter: dependencies.storeKitService.isSupporter
        ).palette.control.color
        return LinearGradient(
            colors: [tint.opacity(0.5), tint.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
