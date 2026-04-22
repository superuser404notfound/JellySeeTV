import SwiftUI

struct CastRow: View {
    let people: [PersonInfo]
    let imageURLProvider: (PersonInfo) -> URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("detail.cast")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 20) {
                    ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                        CastCard(person: person, imageURL: imageURLProvider(person))
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 12)
            }
        }
    }
}

struct CastCard: View {
    let person: PersonInfo
    let imageURL: URL?

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            AsyncCachedImage(url: imageURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                    Text(initials)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            .overlay(
                // Circular accent-color stroke for focus, drawn just
                // outside the portrait edge so the avatar itself stays
                // uncropped. Matches the outer-stroke pattern used for
                // media cards; Circle keeps the ring concentric with
                // the round clip without any corner-radius fiddling.
                Circle()
                    .strokeBorder(.tint, lineWidth: 3)
                    .padding(-3)
                    .opacity(isFocused ? 1 : 0)
            )

            VStack(spacing: 2) {
                Text(person.name)
                    .font(.caption)
                    .lineLimit(1)

                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 100)
        }
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 10, y: 5)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .focusable()
        .focused($isFocused)
    }

    private var initials: String {
        let parts = person.name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(person.name.prefix(2)).uppercased()
    }
}
