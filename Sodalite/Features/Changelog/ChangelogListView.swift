import SwiftUI

/// Settings → "What's New": lists every shipped release; parallel to WhatsNewView modal by design.
struct ChangelogListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(String(
                    localized: "settings.changelog.title",
                    defaultValue: "What's New"
                ))
                .font(.largeTitle)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .padding(.bottom, 32)

                LazyVStack(spacing: 56) {
                    ForEach(Changelog.entries) { entry in
                        VersionSection(entry: entry)
                    }
                }
                .frame(maxWidth: 900)
                .padding(.horizontal, hSizeClass == .compact ? 16 : 80)
                .padding(.bottom, 80)
            }
            .frame(maxWidth: .infinity)
        }
        // Bottom edge-fade "scrollable" cue; wider band (88%→100%) than the modal so it reads through the nav-stack container.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hidesNavigationBarChrome()
        // Belt and braces: catch the Menu button and pop back even if focus drifts off the focusable rows.
        .onExitCommandCompat { dismiss() }
    }
}

private struct VersionSection: View {
    let entry: ChangelogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // "Version" prefix kept verbatim, reads correctly in every shipped locale, no catalog entry needed.
            Text("Version \(entry.version)")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 24) {
                ForEach(entry.highlights) { highlight in
                    HighlightRow(highlight: highlight)
                }
            }
        }
    }
}

private struct HighlightRow: View {
    let highlight: ChangelogHighlight

    // @FocusState not @Environment(\.isFocused): latter doesn't propagate into a plain .focusable() View on tvOS.
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack {
                Circle()
                    .fill(tintForKind.opacity(0.18))
                Image(systemName: highlight.systemImage)
                    .font(.title3)
                    .foregroundStyle(tintForKind)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.title)
                    .font(.body)
                    .fontWeight(.semibold)
                if let description = highlight.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isFocused ? Color.Theme.focusFill : .white.opacity(0.05))
        )
        // Same SettingsTileButtonStyle accent-tint stroke + lift.
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.tint, lineWidth: 3)
                .opacity(isFocused ? 1 : 0)
        )
        .focusResponse(.tile, isFocused: isFocused)
        // Focusable so the tvOS focus engine can step through rows and auto-scroll the list.
        .focusable()
        .focused($isFocused)
    }

    private var tintForKind: Color {
        switch highlight.kind {
        case .new: return .blue
        case .improve: return .green
        case .fix: return .orange
        }
    }
}
