import SwiftUI

/// Radarr/Sonarr request options (quality profile, root folder, tags), shared by the single-title request sheet
/// and the collection bulk request so both submit through the same field set. Renders nothing until the
/// options are resolved, and says so while they are still in flight: an empty section reads as "this server
/// has none", which is exactly what it looked like before.
///
/// Pickers go through `.menuPresentation`, not SwiftUI `Menu`: Menu leaked the Menu-button press up the nav stack
/// during its ~1s close animation and exited the app. That gives tvOS the cover it needs (its own focus
/// environment) and iOS a sheet it can swipe away, which a raw cover never offered (Sodalite#132).
struct SeerrRequestOptionsForm: View {
    let options: SeerrRequestOptions

    @State private var openField: Field?

    private enum Field: String, Identifiable {
        case profile, rootFolder, tags
        var id: String { rawValue }
    }

    var body: some View {
        if let details = options.details {
            fields(details: details)
        } else if options.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("catalog.allRequests.edit.loading")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fields(details: SeerrServiceDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("catalog.request.advanced")
                .font(.title3)
                .fontWeight(.semibold)

            // Stacked full-width: quality-profile names get long ("[German] HD Bluray + WEB") and wrap in a half-width column.
            pickerRow(
                label: "catalog.request.qualityProfile",
                value: profileName(details: details),
                field: .profile
            )
            pickerRow(
                label: "catalog.request.rootFolder",
                value: options.rootFolder ?? String(localized: "catalog.request.rootFolder.default", defaultValue: "Default"),
                field: .rootFolder,
                truncation: .middle
            )
            if !options.availableTags.isEmpty {
                pickerRow(
                    label: "catalog.request.tags",
                    value: tagsLabel,
                    field: .tags
                )
            }
        }
        .menuPresentation(item: $openField) { field in
            panel(for: field, details: details)
        }
    }

    private func pickerRow(
        label: LocalizedStringKey,
        value: String,
        field: Field,
        truncation: Text.TruncationMode = .tail
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                openField = field
            } label: {
                HStack {
                    Text(value)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(truncation)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.Theme.restFill, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(CatalogPickerButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func panel(for field: Field, details: SeerrServiceDetails) -> some View {
        switch field {
        case .profile:
            CatalogPickerSheet(
                title: String(localized: "catalog.request.qualityProfile", defaultValue: "Quality profile"),
                options: details.profiles.map { .init(id: "\($0.id)", label: $0.name) },
                selectedID: options.profileID.map(String.init),
                onSelect: { rawID in
                    if let id = Int(rawID) { options.profileID = id }
                    openField = nil
                },
                onCancel: { openField = nil }
            )
        case .rootFolder:
            CatalogPickerSheet(
                title: String(localized: "catalog.request.rootFolder", defaultValue: "Root folder"),
                options: details.rootFolders.map { .init(id: $0.path, label: $0.path) },
                selectedID: options.rootFolder,
                onSelect: { path in
                    options.rootFolder = path
                    openField = nil
                },
                onCancel: { openField = nil }
            )
        case .tags:
            CatalogMultiSelectSheet(
                title: String(localized: "catalog.request.tags", defaultValue: "Tags"),
                options: options.availableTags.map { .init(id: "\($0.id)", label: $0.label) },
                selectedIDs: Set(options.tagIDs.map(String.init)),
                onCommit: { ids in
                    options.tagIDs = Set(ids.compactMap(Int.init))
                    openField = nil
                },
                onCancel: { openField = nil }
            )
        }
    }

    private func profileName(details: SeerrServiceDetails) -> String {
        if let id = options.profileID,
           let profile = details.profiles.first(where: { $0.id == id }) {
            return profile.name
        }
        return String(localized: "catalog.request.qualityProfile.default", defaultValue: "Default")
    }

    private var tagsLabel: String {
        if options.tagIDs.isEmpty {
            return String(localized: "catalog.request.tags.none", defaultValue: "None")
        }
        return options.availableTags
            .filter { options.tagIDs.contains($0.id) }
            .map(\.label)
            .joined(separator: ", ")
    }
}
