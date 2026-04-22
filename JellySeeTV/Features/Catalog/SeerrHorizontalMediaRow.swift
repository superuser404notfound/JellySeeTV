import SwiftUI

struct SeerrHorizontalMediaRow: View {
    let title: LocalizedStringKey
    let items: [SeerrMedia]
    var isLoadingMore: Bool = false
    var onItemSelected: ((SeerrMedia) -> Void)?
    var onNeedsMore: (() -> Void)?

    // Trigger pagination a few items before the end so the new cards
    // are already in place by the time the focus reaches them.
    private let prefetchThreshold = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 30) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, media in
                        FocusableCard {
                            onItemSelected?(media)
                        } content: { isFocused in
                            SeerrMediaCard(media: media, isFocused: isFocused)
                        }
                        .onAppear {
                            if index >= items.count - prefetchThreshold {
                                onNeedsMore?()
                            }
                        }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .frame(width: 120, height: 330)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}
