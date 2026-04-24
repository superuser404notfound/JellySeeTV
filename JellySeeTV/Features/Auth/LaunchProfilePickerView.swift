import SwiftUI

/// Shown on cold launch when the user has multiple remembered
/// profiles for the active server. Picking a card re-uses the
/// cached token via `switchToUser` — no password re-entry.
///
/// Long-pressing a card opens a confirm-to-forget menu. The
/// "Add another profile" button jumps straight to LoginView for
/// the same server (server discovery is already done).
struct LaunchProfilePickerView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    let server: JellyfinServer

    @State private var rememberedUsers: [RememberedUser] = []
    @State private var navigateToAddProfile = false
    @State private var switchError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                header

                profileGrid

                addProfileButton
                    .focusSection()
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationDestination(isPresented: $navigateToAddProfile) {
                // UserPickerView shows the server's public users with
                // avatars — mirrors the normal login entry point so a
                // second profile feels like "pick another user" rather
                // than "type username+password from scratch".
                UserPickerView(server: server)
            }
            .alert(
                String(localized: "profile.switch.failed.title",
                       defaultValue: "Couldn't switch profile"),
                isPresented: Binding(
                    get: { switchError != nil },
                    set: { if !$0 { switchError = nil } }
                ),
                presenting: switchError
            ) { _ in
                Button(String(localized: "common.ok", defaultValue: "OK")) {
                    switchError = nil
                }
            } message: { message in
                Text(message)
            }
            .onAppear {
                rememberedUsers = dependencies.listRememberedUsers(serverID: server.id)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Text(server.name)
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(
                localized: "profile.launch.subtitle",
                defaultValue: "Who's watching?"
            ))
            .font(.body)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Grid

    private var profileGrid: some View {
        let columnCount = max(1, min(rememberedUsers.count, 5))
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(200), spacing: 32),
                    count: columnCount
                ),
                spacing: 40
            ) {
                ForEach(rememberedUsers) { user in
                    RememberedProfileCard(
                        user: user,
                        server: server,
                        onSelect: { select(user) },
                        onLongPress: { forget(user) }
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .focusSection()
    }

    // MARK: - Add Profile

    private var addProfileButton: some View {
        Button {
            navigateToAddProfile = true
        } label: {
            Label {
                Text(String(
                    localized: "profile.addAnother",
                    defaultValue: "Add another profile"
                ))
            } icon: {
                Image(systemName: "plus.circle")
            }
            .font(.body)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Actions

    private func select(_ user: RememberedUser) {
        do {
            try dependencies.switchToUser(user, server: server)
            // Drop cached thumbnails — they were fetched under the
            // old profile's token which may no longer resolve.
            ImageCache.shared.clear()
            let jf = JellyfinUser(
                id: user.id,
                name: user.name,
                serverID: server.id,
                hasPassword: nil,
                primaryImageTag: user.imageTag
            )
            appState.setAuthenticated(server: server, user: jf)

            // Restore this profile's own remembered Seerr session.
            // If the target profile never signed into Seerr, Seerr
            // stays disconnected and the Catalog tab shows the "set
            // up Seerr" empty state.
            Task { await restoreSeerrForProfile(userID: user.id, serverID: server.id) }
            // Backfill a missing PrimaryImageTag from the server so
            // the Settings avatar switches to the actual picture
            // instead of staying on the initials.
            Task { await refreshUserDetails(userID: user.id, serverID: server.id) }
        } catch {
            switchError = error.localizedDescription
        }
    }

    private func refreshUserDetails(userID: String, serverID: String) async {
        let tag = await fetchFreshImageTag(for: userID)
        guard appState.activeUser?.id == userID else { return }
        guard let current = appState.activeUser else { return }
        guard current.primaryImageTag != tag else { return }

        let fresh = JellyfinUser(
            id: current.id,
            name: current.name,
            serverID: current.serverID,
            hasPassword: current.hasPassword,
            primaryImageTag: tag
        )
        appState.activeUser = fresh
        if let tag, !tag.isEmpty {
            try? dependencies.keychainService.save(tag, for: "activeUserImageTag")
        } else {
            try? dependencies.keychainService.delete(for: "activeUserImageTag")
        }
        if let existing = dependencies.listRememberedUsers(serverID: serverID)
            .first(where: { $0.id == userID }) {
            try? dependencies.rememberUser(
                RememberedUser(
                    id: existing.id,
                    serverID: existing.serverID,
                    name: fresh.name,
                    imageTag: tag,
                    token: existing.token,
                    addedAt: existing.addedAt
                )
            )
        }
    }

    private func fetchFreshImageTag(for userID: String) async -> String? {
        if let me = try? await dependencies.jellyfinAuthService.getCurrentUser(),
           me.id == userID,
           let tag = me.primaryImageTag, !tag.isEmpty {
            return tag
        }
        if let publicUsers = try? await dependencies.jellyfinAuthService.getPublicUsers(),
           let match = publicUsers.first(where: { $0.id == userID }),
           let tag = match.primaryImageTag, !tag.isEmpty {
            return tag
        }
        return nil
    }

    private func restoreSeerrForProfile(userID: String, serverID: String) async {
        guard let seerrServer = dependencies.restoreSeerrSession(
            forJellyfinUserID: userID,
            jellyfinServerID: serverID
        ) else {
            try? dependencies.clearSeerrSession()
            appState.disconnectSeerr()
            return
        }
        if let seerrUser = try? await dependencies.seerrAuthService.currentUser() {
            appState.setSeerrConnected(server: seerrServer, user: seerrUser)
        } else {
            dependencies.forgetRememberedSeerr(
                forJellyfinUserID: userID,
                jellyfinServerID: serverID
            )
            try? dependencies.clearSeerrSession()
            appState.disconnectSeerr()
        }
    }

    private func forget(_ user: RememberedUser) {
        do {
            try dependencies.forgetUser(id: user.id, serverID: server.id)
            rememberedUsers = dependencies.listRememberedUsers(serverID: server.id)

            // If the user forgot the defaultUserID, clear the default
            // so launch behavior doesn't try to restore a ghost.
            if dependencies.authPreferences.defaultUserID == user.id {
                dependencies.authPreferences.defaultUserID = nil
            }
        } catch {
            switchError = error.localizedDescription
        }
    }
}

// MARK: - Card

/// Circular avatar + name card with long-press-to-forget support.
/// Matches the UserPickerCard look so switching between the "server
/// public users" picker and the "remembered profiles" picker feels
/// consistent.
struct RememberedProfileCard: View {
    let user: RememberedUser
    let server: JellyfinServer
    let onSelect: () -> Void
    let onLongPress: () -> Void

    @Environment(\.dependencies) private var dependencies
    @FocusState private var isFocused: Bool

    private let diameter: CGFloat = 160

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 16) {
                avatar
                Text(user.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        // tvOS-native: long-pressing a focusable button opens a
        // context menu instead of firing both the primary action
        // and a secondary gesture on release. Tapping "Remove"
        // inside the menu is the explicit confirmation — one extra
        // click to protect against accidental deletion.
        .contextMenu {
            Button(role: .destructive, action: onLongPress) {
                Label(
                    String(localized: "profile.forget.confirm.short",
                           defaultValue: "Remove profile"),
                    systemImage: "trash"
                )
            }
        }
    }

    private var avatar: some View {
        ZStack {
            if let url = profileImageURL {
                AsyncCachedImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsCircle
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
            } else {
                initialsCircle
                    .frame(width: diameter, height: diameter)
            }
        }
        .overlay(
            Circle()
                .strokeBorder(.tint, lineWidth: 3)
                .padding(-3)
                .opacity(isFocused ? 1 : 0)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .shadow(color: .black.opacity(isFocused ? 0.4 : 0), radius: 20, y: 10)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var initialsCircle: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Text(initials)
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private var initials: String {
        let parts = user.name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(user.name.prefix(2)).uppercased()
    }

    private var profileImageURL: URL? {
        dependencies.jellyfinImageService.userProfileImageURL(
            userID: user.id,
            tag: user.imageTag
        )
    }
}
