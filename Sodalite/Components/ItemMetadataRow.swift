import SwiftUI

/// Shared metadata display row: year · runtime · rating badge · ★ score · optional extras
///
/// Separators sit BETWEEN the segments that survived, not in front of each one. Written the other
/// way the row grew a leading dot as soon as everything ahead of a segment dropped out, which the
/// rating switches (Sodalite#127) turn from a rarity into an everyday case.
struct ItemMetadataRow: View {
    let item: JellyfinItem
    var showRuntime: Bool = true
    var extraContent: (() -> AnyView)?

    @Environment(\.dependencies) private var dependencies

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 { separator }
                segment
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var segments: [AnyView] {
        var out: [AnyView] = []

        if let year = item.productionYear {
            out.append(AnyView(Text(String(year))))
        }

        if showRuntime, let runtime = item.runTimeTicks {
            out.append(AnyView(Text(runtime.ticksToDisplay)))
        }

        if let rating = item.officialRating {
            out.append(AnyView(
                Text(rating)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.secondary.opacity(0.5), lineWidth: 1)
                    )
            ))
        }

        if let score = item.communityRating,
           dependencies.appearancePreferences.showCommunityRating {
            out.append(AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(String(format: "%.1f", score))
                }
            ))
        }

        // RT critic score (needs a provider filling CriticRating, e.g. OMDb); fresh/rotten split at 60, jellyfin-web badge artwork.
        if let critic = item.criticRating,
           dependencies.appearancePreferences.showCriticRating {
            out.append(AnyView(
                HStack(spacing: 5) {
                    Image(critic >= 60 ? "RTFresh" : "RTRotten")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 20)
                    Text(verbatim: "\(Int(critic)) %")
                }
            ))
        }

        if let extra = extraContent {
            out.append(extra())
        }

        return out
    }

    private var separator: some View {
        Text("·").foregroundStyle(.tertiary)
    }
}
