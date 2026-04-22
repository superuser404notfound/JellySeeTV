import SwiftUI

struct SeerrMediaCard: View {
    let media: SeerrMedia
    /// Set by the caller from `FocusableCard`'s content closure, same
    /// pattern as `MediaCard`. Drives the accent-colored focus stroke
    /// around the poster.
    var isFocused: Bool = false

    private let cardWidth: CGFloat = 220
    private let cardHeight: CGFloat = 330

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            posterImage
            itemInfo
        }
        .frame(width: cardWidth)
    }

    private var posterImage: some View {
        AsyncCachedImage(url: SeerrImageURL.poster(path: media.posterPath)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Rectangle()
                    .fill(Color.Theme.surface)
                Image(systemName: iconForType)
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if let status = media.mediaInfo?.status, status != .unknown {
                SeerrStatusBadge(status: status, compact: true)
                    .padding(8)
            }
        }
        .overlay(
            // Outer accent stroke — same pattern as MediaCard. The
            // poster itself stays uncropped and the title text below
            // sits outside the ring.
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(.tint, lineWidth: 3)
                .padding(-3)
                .opacity(isFocused ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        )
    }

    private var itemInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(media.displayTitle)
                .font(.caption)
                .lineLimit(1)

            if let year = media.displayYear {
                Text(year)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconForType: String {
        switch media.mediaType {
        case .movie: "film"
        case .tv: "tv"
        case .person: "person"
        }
    }
}
