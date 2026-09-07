import SwiftUI

/// PIN recovery: prove control of a guardian account via its Jellyfin password (which profiles count is GuardianPINRecoveryCandidates' call); recovery bound to existing server creds.
struct PINRecoveryView: View {
    @Environment(\.dependencies) private var dependencies

    let onRecovered: () -> Void
    let onCancel: () -> Void

    @State private var candidates: [(server: JellyfinServer, user: RememberedUser)] = []
    @State private var selected: RememberedUser?
    @State private var selectedServer: JellyfinServer?
    @State private var password = ""
    @State private var error: LocalizedStringKey?
    @State private var isValidating = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 32) {
                Text("parental.pin.recovery.title")
                    .font(.title2).fontWeight(.semibold)
                Text("parental.pin.recovery.subtitle")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 700)

                if selected == nil {
                    profileList
                } else {
                    passwordEntry
                }

                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                }

                Button(role: .cancel, action: onCancel) {
                    Label("common.cancel", systemImage: "xmark")
                        .padding(.horizontal, 24).padding(.vertical, 12)
                }
                .buttonStyle(SettingsTileButtonStyle())
            }
            .screenContentInset()
        }
        .onAppear(perform: loadCandidates)
    }

    private var profileList: some View {
        VStack(spacing: 8) {
            ForEach(candidates, id: \.user.id) { entry in
                Button {
                    selected = entry.user
                    selectedServer = entry.server
                    error = nil
                } label: {
                    HStack {
                        Text(entry.user.name).font(.body).fontWeight(.medium)
                        Spacer()
                        Text(entry.server.name).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .buttonStyle(SettingsTileButtonStyle())
            }
        }
        .frame(maxWidth: 700)
        .focusSectionCompat()
    }

    private var passwordEntry: some View {
        VStack(spacing: 20) {
            Text(selected?.name ?? "").font(.headline)
            SecureField("auth.password.placeholder", text: $password)
                .textContentType(.password)
                .frame(maxWidth: 500)
            Button {
                Task { await validate() }
            } label: {
                Label("parental.pin.recovery.verify", systemImage: "checkmark.shield")
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .buttonStyle(SettingsTileButtonStyle())
            .disabled(password.isEmpty || isValidating)
        }
        .focusSectionCompat()
    }

    private func loadCandidates() {
        var all: [(server: JellyfinServer, user: RememberedUser)] = []
        for server in dependencies.listKnownServers() {
            for user in dependencies.listRememberedUsers(serverID: server.id) {
                all.append((server: server, user: user))
            }
        }
        candidates = GuardianPINRecoveryCandidates.candidates(
            all,
            role: { dependencies.parentalControlsPreferences.role(
                ProfileRef(serverID: $0.server.id, userID: $0.user.id)) },
            hasOwnPIN: { dependencies.hasOwnPIN(
                ProfileRef(serverID: $0.server.id, userID: $0.user.id)) }
        )
    }

    private func validate() async {
        guard let user = selected, let server = selectedServer else { return }
        isValidating = true
        defer { isValidating = false }
        // login() is a pure REST call; does not mutate the stored session or its token. The borrowed
        // baseURL goes back on EVERY exit, success included: JellyfinClient is process-wide and holds
        // the active session's access token, so a client left pointing at the recovery server sends
        // that token there on every request after this, and only a relaunch or a profile switch
        // points it home again.
        let previousBaseURL = dependencies.jellyfinClient.baseURL
        defer { dependencies.jellyfinClient.baseURL = previousBaseURL }
        dependencies.jellyfinClient.baseURL = dependencies.preferredURL(for: server)
        do {
            _ = try await dependencies.jellyfinAuthService.login(
                username: user.name, password: password
            )
            onRecovered()
        } catch {
            self.error = "parental.pin.recovery.failed"
        }
    }
}
