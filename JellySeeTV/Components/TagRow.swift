import SwiftUI

struct TagRow: View {
    let title: LocalizedStringKey
    let tags: [NamedItem]
    var onTagSelected: ((NamedItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(tags) { tag in
                        TagCard(name: tag.name) {
                            onTagSelected?(tag)
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 12)
            }
        }
    }
}

struct TagCard: View {
    let name: String
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            action()
        } label: {
            Text(name)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(isFocused ? .white.opacity(0.2) : .white.opacity(0.08))
                )
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}
