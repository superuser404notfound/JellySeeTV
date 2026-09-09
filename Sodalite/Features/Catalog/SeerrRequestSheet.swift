import SwiftUI

/// The whole request, in one panel: which seasons it covers, which Radarr/Sonarr options it carries,
/// and the single action that posts it.
///
/// It replaces a flow that was spread over two surfaces (Sodalite#132): the season selection sat
/// mid-page behind an "Add to request" chip, the confirmation sat in the page header, and one button
/// had to mean "take me to the seasons" on the first press and "submit" on the second. Selection and
/// confirmation are one screen now, and the page's season section went back to being a place to
/// browse episodes.
///
/// Shape and chrome follow `SeerrRequestEditSheet`, which already solved this layout for editing an
/// existing request, so requesting and editing look the same. The footer sits outside the scroll
/// area: a 40-season list would otherwise push the primary action off the bottom, and on tvOS that
/// means travelling through 40 focus stops to reach it.
struct SeerrRequestSheet: View {
    let draft: SeerrRequestDraft
    let title: String
    let subtitle: String?
    /// Resolved by the page, which owns the Jellyfin ground-truth reconcile that turns a stale
    /// Seerr "available" into `.deleted`.
    let status: (Int) -> SeerrMediaStatus?
    let onSubmitted: () -> Void
    let onCancel: () -> Void

    @Environment(\.dependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case submit }
    private var isCompact: Bool { hSizeClass == .compact }

    /// The phone in portrait is the one tier that cannot fit the two footer buttons on a line. Measured
    /// on a 402pt iPhone: side by side they want about 390pt, which is more than the 362pt left inside
    /// the panel's padding, so the whole stack overflowed and its 20pt gutter collapsed to 4pt on both
    /// sides. Same split the detail pages use for their action rows.
    private var isPhonePortrait: Bool {
        #if os(iOS)
        hSizeClass == .compact && vSizeClass != .compact
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 18 : 24) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: isCompact ? 20 : 28) {
                    seasonSection
                    SeerrRequestOptionsForm(options: draft.options)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .focusSectionCompat()

            if let error = draft.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(isCompact ? 20 : 48)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        #if os(tvOS)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        #else
        .background(.thinMaterial)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            // Opens on the primary action, with the ticked seasons in view above it: the alternative is
            // the focus engine's own first target, which on a long series is the top of the season list.
            deferOnMain(by: 0.1) { focusedField = .submit }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(isCompact ? .title3 : .title2)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var seasonSection: some View {
        if draft.mediaType == .tv, !draft.seasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("catalog.seasons.title")
                    .font(.title3)
                    .fontWeight(.semibold)

                SeerrSeasonRow(
                    title: allSeasonsTitle,
                    status: nil,
                    isOn: draft.allSeasonsSelected,
                    toggle: {
                        if draft.allSeasonsSelected {
                            draft.clearSelection()
                        } else {
                            draft.selectAll()
                        }
                    }
                )

                ForEach(draft.seasons) { season in
                    SeerrSeasonRow(
                        title: SeerrSeasonRow.seasonTitle(season.seasonNumber),
                        status: status(season.seasonNumber),
                        isOn: draft.isSelected(season.seasonNumber),
                        toggle: { draft.toggle(season.seasonNumber) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if isPhonePortrait {
            // Primary on top, the way the detail pages stack their action rows.
            VStack(spacing: 12) {
                submitButton
                cancelButton
            }
        } else {
            HStack(spacing: 24) {
                cancelButton
                submitButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cancelButton: some View {
        GlassActionButton(
            title: "common.cancel",
            systemImage: "xmark",
            action: onCancel
        )
        .disabled(draft.isSubmitting)
        .frame(maxWidth: isPhonePortrait ? .infinity : nil)
    }

    private var submitButton: some View {
        GlassActionButton(
            title: submitTitle,
            systemImage: "tray.and.arrow.down",
            isProminent: true,
            isLoading: draft.isSubmitting,
            action: submit
        )
        .focused($focusedField, equals: .submit)
        .disabled(draft.isSubmitting || !draft.canSubmit)
        .frame(maxWidth: isPhonePortrait ? .infinity : nil)
    }

    private var allSeasonsTitle: String {
        draft.allSeasonsSelected
            ? String(localized: "catalog.seasons.deselectAll", defaultValue: "Deselect all")
            : String(localized: "catalog.seasons.selectAll", defaultValue: "Select all")
    }

    /// Names the count, which is the feedback the old flow never gave, and the reason preselecting the
    /// missing seasons is safe: a wide selection cannot be submitted without being spelled out.
    private var submitTitle: LocalizedStringKey {
        guard draft.mediaType == .tv else { return "catalog.button.request" }
        switch draft.selectedSeasons.count {
        case 0: return "catalog.button.requestSeasons"
        case 1: return "catalog.request.submit.oneSeason"
        case let count: return "catalog.request.submit.seasons \(count)"
        }
    }

    private func submit() {
        Task {
            if await draft.submit(service: dependencies.seerrRequestService) {
                onSubmitted()
            }
        }
    }
}
