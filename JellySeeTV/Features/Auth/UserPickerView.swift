import SwiftUI

/// Server-side user picker that sits between server discovery and
/// the password/Quick-Connect screen. Fetches `/Users/Public` and
/// shows one avatar-card per user. Tapping a card carries the
/// selected user forward into `LoginView`, so the user never has to
/// type their name.
///
/// Falls back to a manual username field when the server either
/// rejects `/Users/Public` or returns an empty list (admin disabled
/// the "Show users on login screen" option). A "Sign in manually"
/// button below the grid lets advanced users bypass the picker
/// even when users are visible.
struct UserPickerView: View {
    @Environment(\.dependencies) private var dependencies

    let server: JellyfinServer

    @State private var users: [JellyfinUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedUser: JellyfinUser?
    @State private var manualLogin = false

    var body: some View {
        VStack(spacing: 40) {
            header

            if isLoading {
                ProgressView()
                    .frame(maxHeight: .infinity)
            } else if let errorMessage {
                errorState(message: errorMessage)
            } else if users.isEmpty {
                // Server-side list empty — either "show users" is off,
                // or the server is older than 10.x. Same UX as the
                // manual path.
                emptyState
            } else {
                userGrid
            }
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
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
            LoginView(server: server, preSelectedUser: selectedUser)
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
        // Fixed-width columns + Spacer sandwich centers the grid
        // horizontally — .adaptive stretched to full width and pinned
        // a single demo-server user to the left edge.
        //
        // Both the grid and the manual-login button sit in their own
        // .focusSection() blocks. That gives the tvOS focus engine two
        // peer regions: it picks the upper one (grid) for initial
        // focus and lets ↓ walk into the button. Without the grid's
        // section the button stole initial focus because it was the
        // only explicit section on screen.
        let columnCount = max(1, min(users.count, 5))
        return ScrollView {
            VStack(spacing: 120) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(200), spacing: 32),
                            count: columnCount
                        ),
                        spacing: 40
                    ) {
                        ForEach(users) { user in
                            UserPickerCard(user: user, server: server) {
                                selectedUser = user
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .focusSection()

                manualLoginButton
                    .focusSection()
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
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            Text(String(
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
        }
        .frame(maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
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
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Load

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        // Scope the JellyfinClient to the server we're about to pick
        // users from — the server discovery step leaves baseURL at
        // whatever was last used, and /Users/Public needs the correct
        // host.
        dependencies.jellyfinClient.baseURL = server.url
        do {
            users = try await dependencies.jellyfinAuthService.getPublicUsers()
        } catch {
            errorMessage = error.localizedDescription
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
    @FocusState private var isFocused: Bool

    private let diameter: CGFloat = 160

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
        .buttonStyle(.plain)
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
            tag: user.primaryImageTag
        )
    }
}
