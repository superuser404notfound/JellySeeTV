import SwiftUI

/// Sub-components extracted from CatalogDetailView so the main file
/// stays focused on the load/render flow. Lives in the same target,
/// so the previously-private types are simply demoted to internal —
/// nothing outside the catalog feature uses them anyway.

/// Season tab used inside the season selection block. The tab is
/// always selectable for *viewing* — even seasons that are already
/// available get tabs so the user can preview their episodes — but
/// the request action is gated separately inside the detail block.
struct CatalogSeasonTab: View {
    let season: SeerrSeason
    let isViewed: Bool
    let isSelectedForRequest: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if isSelectedForRequest {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
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
        if isAvailable { return AnyShapeStyle(.green.opacity(0.18)) }
        if isSelectedForRequest { return AnyShapeStyle(.tint.opacity(0.18)) }
        return AnyShapeStyle(.white.opacity(0.08))
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
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
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
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Picker Sheet

/// Full-screen picker for the profile / root-folder dropdowns.
/// `.fullScreenCover` gives the sheet its own focus environment —
/// the Menu-button dismisses only this modal, no chance of
/// propagating up to the navigation stack and accidentally
/// exiting the app (which is what happened with SwiftUI `Menu`
/// on tvOS during its close animation).
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
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(CatalogPickerButtonStyle())
                            .focused($focusedID, equals: option.id)
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 80)
                    .padding(.bottom, 60)
                }
            }
        }
        // Menu-button dismisses the sheet; tvOS would otherwise
        // eat the press against an empty focus environment.
        .onExitCommand {
            onCancel()
        }
        .onAppear {
            // Focus the currently-selected option on appear, or the
            // first one if nothing's selected — so the back-press gap
            // never hits an empty focus.
            focusedID = selectedID ?? options.first?.id
        }
    }
}
