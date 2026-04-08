import SwiftUI

struct MediaCard: View {
    let item: JellyfinItem
    let imageURL: URL?
    let width: CGFloat
    let height: CGFloat

    init(item: JellyfinItem, imageURL: URL?, width: CGFloat = 220, height: CGFloat = 330) {
        self.item = item
        self.imageURL = imageURL
        self.width = width
        self.height = height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            posterImage
            itemInfo
        }
        .frame(width: width)
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
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottom) {
            progressOverlay
        }
    }

    private var itemInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(.caption)
                .lineLimit(1)

            if let year = item.productionYear {
                Text(String(year))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if item.type == .episode, let seriesName = item.seriesName {
                Text(seriesName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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
                            .fill(.tint)
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
