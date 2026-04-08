import SwiftUI

struct HorizontalMediaRow: View {
    let title: LocalizedStringKey
    let items: [JellyfinItem]
    let imageURLProvider: (JellyfinItem) -> URL?
    var onItemSelected: ((JellyfinItem) -> Void)?
    var cardStyle: MediaCardStyle = .poster

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 30) {
                    ForEach(items) { item in
                        Button {
                            onItemSelected?(item)
                        } label: {
                            MediaCard(
                                item: item,
                                imageURL: imageURLProvider(item),
                                style: cardStyle
                            )
                        }
                        .buttonStyle(.mediaCard)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}
