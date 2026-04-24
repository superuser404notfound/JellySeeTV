import SwiftUI

/// Manages the profile-switching state for the active Jellyfin
/// server: who's currently signed in, which other remembered
/// profiles are available to swap to, whether the picker runs on
/// every cold launch, and which profile is the default.
struct ProfileSettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    @State private var rememberedUsers: [RememberedUser] = []
    @State private var navigateToAddProfile = false
    @State private var actionError: String?

    private var authPreferences: AuthPreferences {
        dependencies.authPreferences
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                Text(String(localized: "settings.profile.title",
                            defaultValue: "Profile"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)

                currentProfileCard

                otherProfilesSection

                addProfileButton

                launchBehaviorSection
            }
            .padding(.vertical, 60)
            .padding(.horizontal, 80)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToAddProfile) {
            if let server = appState.activeServer {
                // Route through UserPickerView so the user sees the
                // server's public profiles with avatars instead of an
                // empty username field. If the server has the public
                // user list disabled, UserPickerView falls back to the
                // manual sign-in field by itself.
                UserPickerView(server: server)
            }
        }
        .alert(
            String(localized: "profile.switch.failed.title",
                   defaultValue: "Couldn't switch profile"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            ),
            presenting: actionError
        ) { _ in
            Button(String(localized: "common.ok", defaultValue: "OK")) {
                actionError = nil
            }
        } message: { message in
            Text(message)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .loginDidComplete)) { _ in
            // LoginView just flipped activeUser to the brand-new
            // profile. Pop the add-profile stack (LoginView +
            // UserPickerView) back to ProfileSettings so the
            // "Currently signed in" card updates visibly and the
            // user isn't stranded on a stale success checkmark.
            navigateToAddProfile = false
            refresh()
        }
    }

    // MARK: - Current

    private var currentProfileCard: some View {
        VStack(spacing: 16) {
            Text(String(
                localized: "settings.profile.current",
                defaultValue: "Currently signed in"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)

            if let user = appState.activeUser, let server = appState.activeServer {
                VStack(spacing: 12) {
                    SettingsAvatar(
                        user: user,
                        server: server,
                        diameter: 120
                    )
                    Text(user.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(server.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Other profiles

    @ViewBuilder
    private var otherProfilesSection: some View {
        let others = rememberedUsers.filter { $0.id != appState.activeUser?.id }
        if !others.isEmpty, let server = appState.activeServer {
            VStack(spacing: 20) {
                Text(String(
                    localized: "settings.profile.switchTo",
                    defaultValue: "Switch profile"
                ))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(
                    localized: "settings.profile.switchTo.hint",
                    defaultValue: "Tap to switch without signing in again. Long-press to remove."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                let columnCount = max(1, min(others.count, 4))
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(180), spacing: 28),
                            count: columnCount
                        ),
                        spacing: 32
                    ) {
                        ForEach(others) { user in
                            RememberedProfileCard(
                                user: user,
                                server: server,
                                onSelect: { switchTo(user, server: server) },
                                onLongPress: { forget(user) }
                            )
                        }
                    }
                    Spacer(minLength: 0)
                }
                .focusSection()
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Add another

    @ViewBuilder
    private var addProfileButton: some View {
        if appState.activeServer != nil {
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
    }

    // MARK: - Launch behavior

    private var launchBehaviorSection: some View {
        VStack(spacing: 20) {
            Text(String(
                localized: "settings.profile.launch.title",
                defaultValue: "On app launch"
            ))
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                ForEach(AuthPreferences.LaunchBehavior.allCases, id: \.self) { choice in
                    Button {
                        authPreferences.launchBehavior = choice
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: authPreferences.launchBehavior == choice
                                  ? "largecircle.fill.circle"
                                  : "circle")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.label)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(choice.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(20)
                    }
                    .buttonStyle(SettingsTileButtonStyle())
                }
            }

            if authPreferences.launchBehavior == .useDefault {
                defaultProfilePicker
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var defaultProfilePicker: some View {
        VStack(spacing: 12) {
            Text(String(
                localized: "settings.profile.default.title",
                defaultValue: "Default profile"
            ))
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)

            VStack(spacing: 8) {
                ForEach(rememberedUsers) { user in
                    Button {
                        authPreferences.defaultUserID = user.id
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: authPreferences.defaultUserID == user.id
                                  ? "largecircle.fill.circle"
                                  : "circle")
                                .foregroundStyle(.tint)
                            Text(user.name)
                                .font(.body)
                            Spacer()
                        }
                        .padding(16)
                    }
                    .buttonStyle(SettingsTileButtonStyle())
                }
            }
        }
    }

    // MARK: - Actions

    private func refresh() {
        guard let server = appState.activeServer else {
            rememberedUsers = []
            return
        }
        rememberedUsers = dependencies.listRememberedUsers(serverID: server.id)
    }

    private func switchTo(_ user: RememberedUser, server: JellyfinServer) {
        do {
            try dependencies.switchToUser(user, server: server)
            // Cached images were fetched with the previous profile's
            // token, which might not resolve against the server under
            // the new user's permissions. Force-refresh by clearing.
            ImageCache.shared.clear()
            let jf = JellyfinUser(
                id: user.id,
                name: user.name,
                serverID: server.id,
                hasPassword: nil,
                primaryImageTag: user.imageTag
            )
            appState.setAuthenticated(server: server, user: jf)
            refresh()

            // Carry the Seerr session for this profile across the
            // switch — each Jellyfin user has their own Seerr login
            // saved separately in the keychain. If the stored cookie
            // turns out to be invalid we drop it and fall back to a
            // disconnected state; the user re-auths once and it
            // sticks from then on.
            Task { await restoreSeerrForSwitchedProfile(userID: user.id, serverID: server.id) }
            // Refresh the user's details from the server so a nil or
            // stale PrimaryImageTag in the RememberedUser gets
            // backfilled. Older entries (pre backfill-from-picker
            // fix) and legacy migrations sometimes landed with
            // imageTag=nil even though the user has a Jellyfin
            // avatar.
            Task { await refreshUserDetails(userID: user.id, serverID: server.id) }
        } catch {
            actionError = error.localizedDescription
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

    /// Try /Users/Me first, fall back to /Users/Public when it
    /// either failed or came back without a PrimaryImageTag (some
    /// Jellyfin versions only populate the tag on the public
    /// listing, not the authenticated detail endpoint).
    private func fetchFreshImageTag(for userID: String) async -> String? {
        if let me = try? await dependencies.jellyfinAuthService.getCurrentUser(),
           me.id == userID,
           let tag = me.primaryImageTag,
           !tag.isEmpty {
            return tag
        }
        if let publicUsers = try? await dependencies.jellyfinAuthService.getPublicUsers(),
           let match = publicUsers.first(where: { $0.id == userID }),
           let tag = match.primaryImageTag,
           !tag.isEmpty {
            return tag
        }
        return nil
    }

    private func restoreSeerrForSwitchedProfile(userID: String, serverID: String) async {
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
            // Stored cookie no longer valid — forget just this
            // profile's entry so the user only has to re-auth
            // Seerr once, not wipe every remembered profile.
            dependencies.forgetRememberedSeerr(
                forJellyfinUserID: userID,
                jellyfinServerID: serverID
            )
            try? dependencies.clearSeerrSession()
            appState.disconnectSeerr()
        }
    }

    private func forget(_ user: RememberedUser) {
        guard let server = appState.activeServer else { return }
        do {
            try dependencies.forgetUser(id: user.id, serverID: server.id)
            if authPreferences.defaultUserID == user.id {
                authPreferences.defaultUserID = nil
            }
            refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Launch behavior labels

private extension AuthPreferences.LaunchBehavior {
    var label: String {
        switch self {
        case .showPicker:
            String(localized: "settings.profile.launch.picker",
                   defaultValue: "Show profile picker")
        case .useDefault:
            String(localized: "settings.profile.launch.default",
                   defaultValue: "Use default profile")
        }
    }

    var detail: String {
        switch self {
        case .showPicker:
            String(localized: "settings.profile.launch.picker.detail",
                   defaultValue: "Pick who's watching every time the app opens.")
        case .useDefault:
            String(localized: "settings.profile.launch.default.detail",
                   defaultValue: "Skip the picker and sign in as the default profile automatically.")
        }
    }
}

// MARK: - Shared avatar view

/// Mirrors the avatar treatment in the Settings profile header and
/// the user picker card so the same user reads as the same person
/// everywhere in the app.
struct SettingsAvatar: View {
    let user: JellyfinUser
    let server: JellyfinServer
    let diameter: CGFloat

    @Environment(\.dependencies) private var dependencies

    var body: some View {
        ZStack {
            if let url = dependencies.jellyfinImageService.userProfileImageURL(
                userID: user.id,
                tag: user.primaryImageTag
            ) {
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
    }

    private var initialsCircle: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Text(initials)
                .font(.system(size: diameter * 0.35, weight: .semibold, design: .rounded))
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
}
