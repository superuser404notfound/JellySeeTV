import SwiftUI

struct SeerrHorizontalMediaRow: View {
    let title: LocalizedStringKey
    let items: [SeerrMedia]
    var onItemSelected: ((SeerrMedia) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 30) {
                    ForEach(items) { media in
                        FocusableCard {
                            onItemSelected?(media)
                        } content: { _ in
                            SeerrMediaCard(media: media)
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}
