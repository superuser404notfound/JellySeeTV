import SwiftUI

struct TagRow: View {
    let title: LocalizedStringKey
    let tags: [TagCardData]
    var onTagSelected: ((TagCardData) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 30) {
                    ForEach(tags) { tag in
                        GenreCard(data: tag) {
                            onTagSelected?(tag)
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}

struct TagCardData: Identifiable, Sendable {
    let id: String
    let name: String
    let backdropURL: URL?
    let logoURL: URL?
    let isStudio: Bool
}

struct GenreCard: View {
    let data: TagCardData
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        FocusableCard {
            action()
        } content: { _ in
            ZStack(alignment: .bottomLeading) {
                // Background image
                AsyncCachedImage(url: data.backdropURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.Theme.surface, Color.Theme.surfaceElevated],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .frame(width: 320, height: 180)
                .clipped()

                // Dark overlay
                Rectangle()
                    .fill(.black.opacity(0.55))

                // Studio logo or genre name
                if data.isStudio, let logoURL = data.logoURL {
                    AsyncCachedImage(url: logoURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 180, maxHeight: 60)
                            .padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } placeholder: {
                        studioFallbackLabel
                    }
                } else {
                    Text(data.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(width: 320, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var studioFallbackLabel: some View {
        Text(data.name)
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .shadow(radius: 4)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
