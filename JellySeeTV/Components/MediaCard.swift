import SwiftUI

enum MediaCardStyle: Sendable {
    case poster    // Vertical 2:3 (movies, series)
    case landscape // Horizontal 16:9 (episodes, continue watching)
}

struct MediaCard: View {
    let item: JellyfinItem
    let imageURL: URL?
    let style: MediaCardStyle

    /// Propagates from the nearest focusable parent (FocusableCard's
    /// `.focusable()` or the surrounding Button). Drives the
    /// accent-colored stroke around the poster image only — the title
    /// text below stays outside the outline on purpose.
    @Environment(\.isFocused) private var isFocused

    private var cardWidth: CGFloat {
        switch style {
        case .poster: 220
        case .landscape: 360
        }
    }

    private var cardHeight: CGFloat {
        switch style {
        case .poster: 330
        case .landscape: 202
        }
    }

    init(item: JellyfinItem, imageURL: URL?, style: MediaCardStyle = .poster) {
        self.item = item
        self.imageURL = imageURL
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            posterImage
            itemInfo
        }
        .frame(width: cardWidth)
    }

    private var posterImage: some View {
        AsyncCachedImage(url: imageURL) { image in
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
        .overlay(alignment: .bottom) {
            progressOverlay
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.tint, lineWidth: 3)
                .opacity(isFocused ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        )
    }

    private var itemInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayTitle)
                .font(.caption)
                .lineLimit(1)

            if let subtitle = displaySubtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var displayTitle: String {
        if style == .landscape, item.type == .episode {
            if let ep = item.indexNumber {
                return "E\(ep) · \(item.name)"
            }
        }
        return item.name
    }

    private var displaySubtitle: String? {
        if item.type == .episode, let seriesName = item.seriesName {
            if let season = item.parentIndexNumber {
                return "\(seriesName) · S\(season)"
            }
            return seriesName
        }
        if let year = item.productionYear {
            return String(year)
        }
        return nil
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if let playedPercentage = item.userData?.playedPercentage, playedPercentage > 0 {
            GeometryReader { geo in
                VStack {
                    Spacer()
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .frame(height: 4)
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: geo.size.width * playedPercentage / 100, height: 4)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var iconForType: String {
        switch item.type {
        case .movie: "film"
        case .series: "tv"
        case .episode: "play.rectangle"
        case .season: "tv"
        case .musicAlbum, .audio: "music.note"
        default: "photo"
        }
    }
}
