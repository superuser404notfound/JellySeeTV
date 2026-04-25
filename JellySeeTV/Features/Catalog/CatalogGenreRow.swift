import SwiftUI

/// Horizontal scroller of genre tiles. Each tile renders the
/// genre's primary backdrop dimmed with the genre name overlaid,
/// matching Jellyseerr web's discover sliders. Tap navigates to a
/// CatalogFilteredGridView for that filter.
struct CatalogGenreRow: View {
    let titleKey: LocalizedStringKey
    let genres: [SeerrGenreSlide]
    let kind: Kind
    let onSelect: (CatalogFilter) -> Void

    enum Kind { case movie, tv }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleKey)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(genres) { genre in
                        GenreTile(genre: genre) {
                            onSelect(filter(for: genre))
                        }
                    }
                }
                .padding(.horizontal, 80)
                // Match SeerrHorizontalMediaRow vertical padding so
                // the focus halo doesn't clip the row above/below.
                .padding(.vertical, 16)
            }
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

    @FocusState private var isFocused: Bool

    private let width: CGFloat = 320
    private let height: CGFloat = 180

    var body: some View {
        Button(action: action) {
            ZStack {
                if let path = genre.primaryBackdrop,
                   let url = SeerrImageURL.backdrop(path: path, size: .w780) {
                    AsyncCachedImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        fallbackBackground
                    }
                    .frame(width: width, height: height)
                    .clipped()
                } else {
                    fallbackBackground
                }

                LinearGradient(
                    colors: [.black.opacity(0.2), .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(genre.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, lineWidth: 4)
                    .opacity(isFocused ? 1 : 0)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 18, y: 8)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }

    private var fallbackBackground: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: width, height: height)
    }
}
