import SwiftUI

/// Radarr/Sonarr request options (quality profile, root folder, tags), shared by the single-title request sheet
/// and the collection bulk request so both submit through the same field set.
///
/// Pickers go through `.menuPresentation`, not SwiftUI `Menu`: Menu leaked the Menu-button press up the nav stack
/// during its ~1s close animation and exited the app. That gives tvOS the cover it needs (its own focus
/// environment) and iOS a sheet it can swipe away, which a raw cover never offered (Sodalite#132).
struct SeerrRequestOptionsForm: View {
    let details: SeerrServiceDetails
    @Binding var selectedProfileID: Int?
    @Binding var selectedRootFolder: String?
    @Binding var selectedTagIDs: Set<Int>

    @State private var isProfilePickerPresented = false
    @State private var isRootFolderPickerPresented = false
    @State private var isTagPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("catalog.request.advanced")
                .font(.title3)
                .fontWeight(.semibold)

            // Stacked full-width: quality-profile names get long ("[German] HD Bluray + WEB") and wrap in a half-width column.
            profilePicker
            rootFolderPicker

            if let tags = details.tags, !tags.isEmpty {
                tagPicker(tags: tags)
            }
        }
    }

    private var profilePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("catalog.request.qualityProfile")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isProfilePickerPresented = true
            } label: {
                HStack {
                    Text(selectedProfileName)
                        .fontWeight(.medium)
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
            .menuPresentation(isPresented: $isProfilePickerPresented) {
                CatalogPickerSheet(
                    title: String(localized: "catalog.request.qualityProfile", defaultValue: "Quality profile"),
                    options: details.profiles.map { .init(id: "\($0.id)", label: $0.name) },
                    selectedID: selectedProfileID.map(String.init),
                    onSelect: { rawID in
                        if let id = Int(rawID) {
                            selectedProfileID = id
                        }
                        isProfilePickerPresented = false
                    },
                    onCancel: { isProfilePickerPresented = false }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rootFolderPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("catalog.request.rootFolder")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isRootFolderPickerPresented = true
            } label: {
                HStack {
                    Text(selectedRootFolder ?? String(localized: "catalog.request.rootFolder.default", defaultValue: "Default"))
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
            .menuPresentation(isPresented: $isRootFolderPickerPresented) {
                CatalogPickerSheet(
                    title: String(localized: "catalog.request.rootFolder", defaultValue: "Root folder"),
                    options: details.rootFolders.map { .init(id: $0.path, label: $0.path) },
                    selectedID: selectedRootFolder,
                    onSelect: { path in
                        selectedRootFolder = path
                        isRootFolderPickerPresented = false
                    },
                    onCancel: { isRootFolderPickerPresented = false }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedProfileName: String {
        if let id = selectedProfileID,
           let profile = details.profiles.first(where: { $0.id == id }) {
            return profile.name
        }
        return String(localized: "catalog.request.qualityProfile.default", defaultValue: "Default")
    }

    private func tagPicker(tags: [SeerrTag]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("catalog.request.tags")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                isTagPickerPresented = true
            } label: {
                HStack {
                    Text(selectedTagsLabel(tags: tags))
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
            .menuPresentation(isPresented: $isTagPickerPresented) {
                CatalogMultiSelectSheet(
                    title: String(localized: "catalog.request.tags", defaultValue: "Tags"),
                    options: tags.map { .init(id: "\($0.id)", label: $0.label) },
                    selectedIDs: Set(selectedTagIDs.map(String.init)),
                    onCommit: { ids in
                        selectedTagIDs = Set(ids.compactMap(Int.init))
                        isTagPickerPresented = false
                    },
                    onCancel: { isTagPickerPresented = false }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func selectedTagsLabel(tags: [SeerrTag]) -> String {
        if selectedTagIDs.isEmpty {
            return String(localized: "catalog.request.tags.none", defaultValue: "None")
        }
        let names = tags
            .filter { selectedTagIDs.contains($0.id) }
            .map(\.label)
        return names.joined(separator: ", ")
    }
}

/// Resolves the default Radarr/Sonarr server and its profile/root-folder defaults for a request.
/// Jellyseerr's `activeProfileId` can be nil, 0 or stale, so the configured default is validated against the
/// profiles the server actually returned before it is used; an unvalidated id shipped in the request and failed.
enum SeerrRequestDefaults {
    struct Resolved {
        let details: SeerrServiceDetails
        let profileID: Int?
        let rootFolder: String?
    }

    static func resolve(
        service: SeerrServiceConfigServiceProtocol,
        mediaType: SeerrMediaType
    ) async throws -> Resolved? {
        let servers: [SeerrServiceServer]
        switch mediaType {
        case .movie: servers = try await service.radarrServers()
        case .tv: servers = try await service.sonarrServers()
        case .person, .unknown: return nil
        }
        guard let chosen = servers.first(where: { $0.isDefault == true }) ?? servers.first else {
            return nil
        }
        let details: SeerrServiceDetails
        switch mediaType {
        case .movie: details = try await service.radarrDetails(serverID: chosen.id)
        case .tv: details = try await service.sonarrDetails(serverID: chosen.id)
        case .person, .unknown: return nil
        }

        let validProfileIDs = Set(details.profiles.map(\.id))
        let profileID = [chosen.activeProfileId, details.server.activeProfileId]
            .compactMap { $0 }
            .first(where: validProfileIDs.contains)
            ?? details.profiles.first?.id

        let validRootFolders = Set(details.rootFolders.map(\.path))
        let rootFolder = [chosen.activeDirectory, details.server.activeDirectory]
            .compactMap { $0 }
            .first(where: validRootFolders.contains)
            ?? details.rootFolders.first?.path

        return Resolved(details: details, profileID: profileID, rootFolder: rootFolder)
    }
}
