import SwiftUI

struct HorizontalMediaRow: View {
    let title: LocalizedStringKey
    let items: [JellyfinItem]
    let imageURLProvider: (JellyfinItem) -> URL?
    var onItemSelected: ((JellyfinItem) -> Void)?
    var cardWidth: CGFloat = 220
    var cardHeight: CGFloat = 330

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(items) { item in
                        Button {
                            onItemSelected?(item)
                        } label: {
                            MediaCard(
                                item: item,
                                imageURL: imageURLProvider(item),
                                width: cardWidth,
                                height: cardHeight
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 50)
            }
        }
    }
}
