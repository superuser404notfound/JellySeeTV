import SwiftUI

/// Sub-components extracted from CatalogDetailView; internal, used only within the catalog feature.

/// Season tab in the season selector. Always selectable for viewing (preview episodes of already-available seasons); the request action is gated separately in the detail block.
struct CatalogSeasonTab: View {
    let season: SeerrSeason
    let isViewed: Bool
    let isSelectedForRequest: Bool
    /// Pipeline status, `nil` when no request exists. Kept distinct (available=green check, processing=blue, pending=orange clock) so "ready to play" reads differently from "waiting for admin approval".
    let availabilityStatus: SeerrMediaStatus?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Selection and status can both apply (status never blocks a re-request), so the picked-checkmark shows alongside the pipeline icon.
                if isSelectedForRequest {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
                if let status = availabilityStatus {
                    Image(systemName: status.systemImage)
                        .font(.caption)
                        .foregroundStyle(status.color)
                }
                Text(seasonTitle)
                    .font(.body)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(background, in: Capsule())
        }
        .buttonStyle(SeasonChipButtonStyle())
    }

    private var seasonTitle: String {
        let label = String(localized: "catalog.season", defaultValue: "Season")
        return "\(label) \(season.seasonNumber)"
    }

    private var background: some ShapeStyle {
        if isViewed { return AnyShapeStyle(.tint.opacity(0.35)) }
        if isSelectedForRequest { return AnyShapeStyle(.tint.opacity(0.18)) }
        if let status = availabilityStatus {
            return AnyShapeStyle(status.color.opacity(0.18))
        }
        return AnyShapeStyle(Color.Theme.restFill)
    }
}

struct SeasonChipButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                Capsule()
                    .strokeBorder(.tint, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
            .focusResponse(.chip, isFocused: isFocused)
    }
}

// MARK: - Picker Button Style

struct CatalogPickerButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.tint, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
            .focusResponse(.inline, isFocused: isFocused)
    }
}

// MARK: - Picker Sheet

/// Full-screen picker for profile / root-folder dropdowns. `.fullScreenCover` isolates the focus environment so Menu-button dismisses only this modal; SwiftUI `Menu` on tvOS leaked the press up the nav stack and exited the app during its close animation.
struct CatalogPickerSheet: View {
    struct Option: Identifiable {
        let id: String
        let label: String
    }

    let title: String
    let options: [Option]
    let selectedID: String?
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @FocusState private var focusedID: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            VStack(spacing: 32) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 60)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option.id)
                            } label: {
                                HStack {
                                    Text(option.label)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Spacer()
                                    if option.id == selectedID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 18)
                                .frame(maxWidth: .infinity)
                                .background(Color.Theme.restFill, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(CatalogPickerButtonStyle())
                            .focused($focusedID, equals: option.id)
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, hSizeClass == .compact ? 20 : 80)
                    .padding(.bottom, 60)
                }
            }
        }
        .onExitCommandCompat {
            onCancel()
        }
        .onAppear {
            // Focus selected (or first) option so the back-press gap never hits an empty focus.
            focusedID = selectedID ?? options.first?.id
        }
    }
}

// MARK: - Multi-Select Sheet

/// Multi-select sibling of `CatalogPickerSheet`: rows toggle membership instead of dismissing; Menu-button (back) commits the selection. Used by the Tags picker for one-or-more Sonarr/Radarr labels.
struct CatalogMultiSelectSheet: View {
    struct Option: Identifiable {
        let id: String
        let label: String
    }

    let title: String
    let options: [Option]
    let selectedIDs: Set<String>
    let onCommit: (Set<String>) -> Void

    @State private var selection: Set<String> = []
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @FocusState private var focusedID: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            VStack(spacing: 32) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 60)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(options) { option in
                            Button {
                                if selection.contains(option.id) {
                                    selection.remove(option.id)
                                } else {
                                    selection.insert(option.id)
                                }
                            } label: {
                                HStack {
                                    Text(option.label)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Spacer()
                                    if selection.contains(option.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 18)
                                .frame(maxWidth: .infinity)
                                .background(Color.Theme.restFill, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(CatalogPickerButtonStyle())
                            .focused($focusedID, equals: option.id)
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, hSizeClass == .compact ? 20 : 80)
                    .padding(.bottom, 60)
                }
            }
        }
        .onExitCommandCompat {
            // Menu-button commits the selection; multi-select has no explicit Cancel state.
            onCommit(selection)
        }
        .onAppear {
            selection = selectedIDs
            focusedID = options.first?.id
        }
    }
}
