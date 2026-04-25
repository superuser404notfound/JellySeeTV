import SwiftUI

/// Horizontal scroller of streaming-network or movie-studio tiles.
/// Each tile renders the provider's TMDB logo on a dark card; tap
/// pushes a CatalogFilteredGridView for the matching network/studio
/// filter. Mirrors Jellyseerr web's CompanyCard slider.
struct CatalogProviderRow: View {
    let titleKey: LocalizedStringKey
    let providers: [CatalogProvider]
    /// The destination is decided by the caller — Catalog wraps the
    /// provider in a Jellyseerr-backed `CatalogFilter`, Home translates
    /// it into a Jellyfin Studios filter against the local library.
    let onSelect: (CatalogProvider) -> Void

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
                            onSelect(provider)
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 16)
            }
        }
    }
}

private struct ProviderTile: View {
    let provider: CatalogProvider
    let action: () -> Void

    private let width: CGFloat = 280
    private let height: CGFloat = 140

    var body: some View {
        // Same reason as GenreTile / SeerrMediaCard / etc. — Button
        // on tvOS layers a system white halo we can't disable, so we
        // route through FocusableCard for a consistent tint outline.
        FocusableCard(action: action) { isFocused in
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
        }
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
