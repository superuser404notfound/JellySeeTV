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
    /// Optional resolver for a sample backdrop per provider. The
    /// caller decides whether the sample comes from the local
    /// Jellyfin library (home) or Jellyseerr discover (catalog) — the
    /// row just renders whatever URL it gets, with a graceful fallback
    /// to the dark logo-only tile when the lookup returns nil.
    var backdropFor: (CatalogProvider) -> URL? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleKey)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 24) {
                    ForEach(providers) { provider in
                        ProviderTile(
                            provider: provider,
                            backdropURL: backdropFor(provider)
                        ) {
                            onSelect(provider)
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 16)
            }
        }
    }
}

private struct ProviderTile: View {
    let provider: CatalogProvider
    let backdropURL: URL?
    let action: () -> Void

    // Match the genre tile dimensions so provider + genre rows
    // line up visually when they sit on the same screen (catalog
    // discover surface, home page).
    private let width: CGFloat = 320
    private let height: CGFloat = 180

    var body: some View {
        // Same reason as GenreTile / SeerrMediaCard / etc. — Button
        // on tvOS layers a system white halo we can't disable, so we
        // route through FocusableCard for a consistent tint outline.
        FocusableCard(action: action) { isFocused in
            ZStack {
                if let backdropURL {
                    AsyncCachedImage(url: backdropURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color(white: 0.08)
                    }
                    .frame(width: width, height: height)
                    .clipped()

                    // Slightly heavier than the genre tile gradient
                    // so the duotone logo on top stays readable even
                    // against bright backdrops.
                    LinearGradient(
                        colors: [.black.opacity(0.55), .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    Color(white: 0.08)
                }

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
