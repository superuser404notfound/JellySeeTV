import SwiftUI

/// Avatar-card picker over `/Users/Public`; carries the selected user into `LoginView`. Falls back to a manual username field when the list is rejected/empty ("Show users on login screen" off).
struct UserPickerView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let server: JellyfinServer
    var addMode: Bool = false
    var onCompletion: (() -> Void)? = nil

    @State private var users: [JellyfinUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedUser: JellyfinUser?
    @State private var manualLogin = false
    /// True when /Users/Public returned profiles but all are already remembered: empty state says so instead of "no users visible".
    @State private var allProfilesAlreadyAdded = false

    var body: some View {
        VStack(spacing: 40) {
            header

            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if let errorMessage {
                errorState(message: errorMessage)
            } else if users.isEmpty {
                emptyState
            } else {
                userGrid
            }
        }
        .screenContentInset()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadUsers()
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedUser != nil || manualLogin },
            set: { active in
                if !active {
                    selectedUser = nil
                    manualLogin = false
                }
            }
        )) {
            LoginView(
                server: server,
                preSelectedUser: selectedUser,
                addMode: addMode,
                onCompletion: onCompletion
            )
            .themedNavigationDestination()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Text(server.name)
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(
                localized: "auth.users.title",
                defaultValue: "Who's watching?"
            ))
            .font(.body)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - User Grid

    private var userGrid: some View {
        // Fixed-width columns + Spacer sandwich centers the grid (.adaptive pinned a single user to the left edge).
        // Grid and manual-login button each get their own .focusSection() so the focus engine picks the grid for initial focus; without the grid's section the button stole it.
        #if os(tvOS)
        let maxCols = 5
        #else
        let maxCols = hSizeClass == .compact ? 2 : 4
        #endif
        let columnCount = max(1, min(users.count, maxCols))
        let m = LayoutMetrics.current(hSizeClass)
        return ScrollView {
            VStack(spacing: hSizeClass == .compact ? 48 : 120) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(m.profileCardSize.width), spacing: 28),
                            count: columnCount
                        ),
                        spacing: 32
                    ) {
                        ForEach(users) { user in
                            UserPickerCard(user: user, server: server) {
                                selectedUser = user
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .focusSectionCompat()

                manualLoginButton
                    .focusSectionCompat()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Manual Fallback

    private var manualLoginButton: some View {
        Button {
            manualLogin = true
        } label: {
            Text(String(
                localized: "auth.users.manual",
                defaultValue: "Sign in with a different account"
            ))
            .font(.body)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .buttonStyle(SettingsTileButtonStyle())
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: hSizeClass == .compact ? 44 : 60))
                .foregroundStyle(.tertiary)
            Text(allProfilesAlreadyAdded
                ? String(
                    localized: "auth.users.allAdded",
                    defaultValue: "All profiles on this server are already added."
                )
                : String(
                    localized: "auth.users.empty",
                    defaultValue: "No users visible from the server. Sign in manually instead."
                ))
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 600)
            Button {
                manualLogin = true
            } label: {
                Text(String(
                    localized: "auth.users.signIn",
                    defaultValue: "Sign in"
                ))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
            }
            .buttonStyle(SettingsTileButtonStyle())
        }
        .frame(maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: hSizeClass == .compact ? 44 : 60))
                .foregroundStyle(.tertiary)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            HStack(spacing: 16) {
                Button {
                    Task { await loadUsers() }
                } label: {
                    Text("home.retry")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .buttonStyle(SettingsTileButtonStyle())
                Button {
                    manualLogin = true
                } label: {
                    Text(String(
                        localized: "auth.users.signIn",
                        defaultValue: "Sign in"
                    ))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .buttonStyle(SettingsTileButtonStyle())
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Load

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        // Scope JellyfinClient to this server: discovery leaves baseURL stale, and /Users/Public needs
        // the right host. Probed rather than guessed, because the last route that worked is not the
        // one that works from here: away from home the LAN slot has to lose to the external one, and
        // nothing else in the sign-in flow asks.
        await dependencies.resolveSignInRoute(for: server)
        do {
            let fetched = try await dependencies.jellyfinAuthService.getPublicUsers()
            // Hide already-remembered profiles (re-adding overwrites the same entry). No-op on first login; re-auth a stale token by forgetting first (long-press).
            let remembered = Set(
                dependencies.listRememberedUsers(serverID: server.id).map(\.id)
            )
            users = fetched.filter { !remembered.contains($0.id) }
            allProfilesAlreadyAdded = !fetched.isEmpty && users.isEmpty
        } catch {
            errorMessage = ErrorText.user(for: error)
        }
        isLoading = false
    }
}

// MARK: - Card

private struct UserPickerCard: View {
    let user: JellyfinUser
    let server: JellyfinServer
    let action: () -> Void

    @Environment(\.dependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @FocusState private var isFocused: Bool

    private var diameter: CGFloat { hSizeClass == .compact ? 110 : 160 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                avatar
                Text(user.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        // BareButtonStyle suppresses tvOS' default thick white focus halo; the avatar's tint ring is the focus affordance (matches LaunchProfilePicker / settings grid).
        .buttonStyle(BareButtonStyle())
        .focused($isFocused)
    }

    private var avatar: some View {
        ZStack {
            if let url = profileImageURL {
                AsyncCachedImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
            // Not `.focusStroke`: padded outward, so it rings the avatar rather than sitting on its
            // edge. A circle offset outward is still a circle, so there is no radius to keep in step.
            Circle()
                .strokeBorder(.tint, lineWidth: FocusStroke.width)
                .padding(-FocusStroke.width)
                .opacity(isFocused ? 1 : 0)
        )
        .focusResponse(.card, isFocused: isFocused)
    }

    private var initialsCircle: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Text(initials)
                .font(.system(size: hSizeClass == .compact ? 38 : 52, weight: .semibold, design: .rounded))
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
            tag: user.primaryImageTag
        )
    }
}
