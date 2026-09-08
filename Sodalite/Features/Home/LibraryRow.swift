import SwiftUI

/// "My Media" row: one tile per video library, opening it in the shared FilteredGridView.
struct LibraryRow: View {
    let titleKey: LocalizedStringKey
    let libraries: [JellyfinLibrary]
    let onSelect: (JellyfinLibrary) -> Void

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
                    ForEach(libraries) { library in
                        LibraryTile(library: library) {
                            onSelect(library)
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

private struct LibraryTile: View {
    let library: JellyfinLibrary
    let action: () -> Void

    @Environment(\.dependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var hSizeClass
    // The shared 16:9 tile size (see LayoutMetrics.landscapeSize).
    private var size: CGSize {
        LayoutMetrics.current(hSizeClass)
            .tileSize(cardScale: dependencies.appearancePreferences.cardScale)
    }

    /// Off by default, because a library image nearly always has the library's own name burnt into
    /// it and drawing ours on top reads as two captions on one tile. A viewer whose images carry no
    /// text turns it on and gets the name in the app's own font, like the Genres row below
    /// (Sodalite#84).
    private var drawsNameOverArtwork: Bool {
        dependencies.appearancePreferences.showLibraryNames
    }

    var body: some View {
        ArtworkTile(
            title: drawsNameOverArtwork ? library.name : nil,
            artworkURL: dependencies.jellyfinImageService.libraryArtworkURL(for: library),
            size: size,
            action: action
        ) {
            ZStack {
                ArtworkTileSurface()

                // The icon sits in the corner rather than above the name, which on a compact tile
                // would overlap it.
                Image(systemName: symbol(for: library.libraryType))
                    .font(.system(size: size.height * 0.22))
                    .foregroundStyle(.tint)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Only when the tile above is unlabelled, else ArtworkTile draws a second copy of
                // the name right on top of this one.
                if !drawsNameOverArtwork {
                    ArtworkTileLabel(title: library.name)
                }
            }
        }
        .accessibilityLabel(library.name)
    }

    private func symbol(for type: LibraryType) -> String {
        switch type {
        case .movies: "film"
        case .tvshows: "tv"
        case .homevideos: "video"
        case .boxsets: "square.stack"
        case .playlists: "list.bullet"
        default: "rectangle.stack"
        }
    }
}
