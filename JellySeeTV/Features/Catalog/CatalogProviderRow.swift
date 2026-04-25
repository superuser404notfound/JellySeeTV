import SwiftUI

/// Horizontal scroller of streaming-network or movie-studio tiles.
/// Each tile renders the provider's TMDB logo on a dark card; tap
/// pushes a CatalogFilteredGridView for the matching network/studio
/// filter. Mirrors Jellyseerr web's CompanyCard slider.
struct CatalogProviderRow: View {
    let titleKey: LocalizedStringKey
    let providers: [CatalogProvider]
    let kind: Kind
    let onSelect: (CatalogFilter) -> Void

    enum Kind { case network, studio }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleKey)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(providers) { provider in
                        ProviderTile(provider: provider) {
                            onSelect(filter(for: provider))
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 16)
            }
        }
    }

    private func filter(for provider: CatalogProvider) -> CatalogFilter {
        switch kind {
        case .network: .tvNetwork(id: provider.id, name: provider.name)
        case .studio: .movieStudio(id: provider.id, name: provider.name)
        }
    }
}

private struct ProviderTile: View {
    let provider: CatalogProvider
    let action: () -> Void

    @FocusState private var isFocused: Bool

    private let width: CGFloat = 280
    private let height: CGFloat = 140

    var body: some View {
        Button(action: action) {
            ZStack {
                Color(white: 0.08)

                if let url = SeerrImageURL.duotoneLogo(path: provider.logoPath) {
                    AsyncCachedImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(28)
                    } placeholder: {
                        nameLabel
                    }
                } else {
                    nameLabel
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, lineWidth: 4)
                    .opacity(isFocused ? 1 : 0)
            )
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 18, y: 8)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }

    private var nameLabel: some View {
        Text(provider.name)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }
}
