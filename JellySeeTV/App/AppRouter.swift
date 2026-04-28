import SwiftUI

struct AppRouter: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    /// Tracks whether the initial session restore + splash has already
    /// run for this process. SwiftUI re-fires `.task` when the AppRouter
    /// view temporarily disappears (e.g. while the UIKit-presented
    /// player modal is on screen) — without this guard, returning from
    /// the player would show the launch splash again.
    @State private var hasRestored = false

    /// Non-nil while the launch-time profile picker is armed: the
    /// restore found a valid session + at least one remembered
    /// profile, and the user either set launchBehavior=.showPicker
    /// or has no default profile pinned. Picking a profile flips
    /// isAuthenticated=true which hides the picker automatically.
    @State private var launchPickerServer: JellyfinServer?

    /// Holds the JellyfinItem fetched for an incoming deep link
    /// (TopShelf cell tap, custom URL invocation). The fullScreenCover
    /// drives off this — non-nil = sheet shown.
    @State private var deepLinkItem: JellyfinItem?

    var body: some View {
        ZStack {
            if appState.isAuthenticated {
                TabRootView()
            } else if let server = launchPickerServer {
                LaunchProfilePickerView(server: server)
            } else {
                ServerDiscoveryView()
            }

            // Splash overlays everything until both the session restore
            // has finished AND the minimum display time has elapsed —
            // then it fades out to reveal whichever root view is now
            // appropriate. Cross-fade looks nicer than the old spinner-
            // then-content swap and prevents a jarring snap when restore
            // completes in <100 ms.
            if appState.isLoading {
                SplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: appState.isLoading)
        .task {
            guard !hasRestored else { return }
            hasRestored = true
            await restoreSession()
        }
        .task(id: appState.pendingDeepLinkItemID) {
            await resolvePendingDeepLink()
        }
        .task(id: appState.requestContinueWatching) {
            await resolveContinueWatchingRequest()
        }
        .fullScreenCover(item: $deepLinkItem) { item in
            NavigationStack {
                DetailRouterView(item: item)
            }
        }
    }

    /// Fetches the active user's first Resume-queue item and feeds
    /// it through the normal deep-link channel. Triggered by
    /// `ContinueWatchingIntent` (Siri / Shortcuts) — the intent
    /// itself stays trivial so tvOS-Siri's "no async work" policy
    /// for voice invocation is respected.
    private func resolveContinueWatchingRequest() async {
        guard appState.requestContinueWatching else { return }

        // Same cold-launch wait as the deep-link path: Siri may
        // hand us control before restoreSession finishes.
        while !appState.isAuthenticated, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard let user = appState.activeUser else {
            appState.requestContinueWatching = false
            return
        }

        let response = try? await dependencies.jellyfinLibraryService.getResumeItems(
            userID: user.id,
            mediaType: "Video",
            limit: 1
        )
        appState.requestContinueWatching = false
        if let item = response?.items.first {
            appState.pendingDeepLinkItemID = item.id
        }
    }

    /// Wait until the user is authenticated, fetch the item from
    /// Jellyfin, then trigger the fullScreenCover. Cleared on the way
    /// out so a second tap on the same TopShelf cell re-fires.
    private func resolvePendingDeepLink() async {
        guard let id = appState.pendingDeepLinkItemID else { return }
        // Cold-launch race: the URL arrives before restoreSession
        // finishes. Wait it out — the TopShelf cell can't have been
        // produced without a valid session in the first place.
        while !appState.isAuthenticated, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard let user = appState.activeUser else {
            appState.pendingDeepLinkItemID = nil
            return
        }
        let item = try? await dependencies.jellyfinItemService.getItemDetail(
            userID: user.id,
            itemID: id
        )
        appState.pendingDeepLinkItemID = nil
        deepLinkItem = item
    }

    private func restoreSession() async {
        appState.isLoading = true
        let splashStart = Date()
        await performRestore()

        // Hold the splash for at least the minimum so the brand moment
        // isn't reduced to a flash on a fast restore path.
        let elapsed = Date().timeIntervalSince(splashStart)
        let remaining = SplashView.minimumDisplayDuration - elapsed
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        appState.isLoading = false
    }

    private func performRestore() async {
        // Fire-and-forget: StoreKit lookups are independent of the
        // Jellyfin restore and shouldn't block the splash. The observable
        // isSupporter flag starts from the cached value and flips live
        // once the async refresh completes.
        Task { @MainActor in
            await dependencies.storeKitService.refreshSupporterStatus()
            await dependencies.storeKitService.loadProducts()
        }

        guard dependencies.restoreSession() else { return }

        guard let serverData = try? dependencies.keychainService.loadData(for: "activeServer"),
              let server = try? JSONDecoder().decode(JellyfinServer.self, from: serverData),
              let userID = try? dependencies.keychainService.loadString(for: KeychainKeys.userID(serverID: server.id)),
              let userName = try? dependencies.keychainService.loadString(for: "activeUserName")
        else {
            try? dependencies.clearSession()
            return
        }

        // primaryImageTag is optional in the keychain — users without
        // a custom avatar never had one persisted. Missing = initials.
        let imageTag = try? dependencies.keychainService.loadString(for: "activeUserImageTag")
        let restored = JellyfinUser(
            id: userID,
            name: userName,
            serverID: server.id,
            hasPassword: nil,
            primaryImageTag: imageTag
        )

        // Migrate pre-0.3.0 sessions into the remembered-profiles
        // list. Legacy installs only persisted the active session —
        // without this, the "Add another profile" flow would show
        // the currently signed-in user in the picker (since no
        // remembered entry existed to filter by).
        if let token = try? dependencies.keychainService.loadString(
            for: KeychainKeys.accessToken(serverID: server.id)
        ), !dependencies.listRememberedUsers(serverID: server.id)
            .contains(where: { $0.id == userID }) {
            try? dependencies.rememberUser(
                RememberedUser(
                    id: userID,
                    serverID: server.id,
                    name: userName,
                    imageTag: imageTag,
                    token: token
                )
            )
        }

        // Multi-profile routing. Four possible outcomes:
        //
        // - .useDefault + defaultUserID points at a remembered
        //   profile → restore that one (switchToUser if it differs
        //   from the last-active one).
        // - .showPicker + remembered profiles exist → arm the
        //   launch picker; don't setAuthenticated yet.
        // - Launch mode says "default" but the default is missing /
        //   was forgotten → fall back to the picker if we have
        //   something to pick from.
        // - Single-profile install or nothing remembered → the
        //   original behavior: restore and auto-enter the app.
        let remembered = dependencies.listRememberedUsers(serverID: server.id)
        let prefs = dependencies.authPreferences

        let shouldUseDefault = prefs.launchBehavior == .useDefault
            && prefs.defaultUserID.flatMap { id in remembered.first { $0.id == id } } != nil

        if shouldUseDefault,
           let defaultID = prefs.defaultUserID,
           let target = remembered.first(where: { $0.id == defaultID }) {
            if target.id != userID {
                try? dependencies.switchToUser(target, server: server)
            }
            let user = JellyfinUser(
                id: target.id,
                name: target.name,
                serverID: server.id,
                hasPassword: nil,
                primaryImageTag: target.imageTag
            )
            appState.setAuthenticated(server: server, user: user)
        } else if remembered.count > 1 {
            launchPickerServer = server
            // Fall through — Seerr restore is independent of which
            // Jellyfin profile ends up active and we want that state
            // ready by the time the user taps a profile.
        } else {
            // Single-profile install (or nothing remembered yet).
            // Enter the app directly — no point showing a picker
            // with one card on it.
            appState.setAuthenticated(server: server, user: restored)
        }

        // Seerr restore — prefer the profile-scoped session when the
        // active user has one saved, fall back to the global
        // last-used entry so legacy (pre-0.3.0) Seerr logins still
        // come back on first upgrade.
        let activeUserID = appState.activeUser?.id
        let activeServerID = appState.activeServer?.id
        let scopedSeerrServer: SeerrServer? = {
            guard let uid = activeUserID, let sid = activeServerID else { return nil }
            return dependencies.restoreSeerrSession(forJellyfinUserID: uid, jellyfinServerID: sid)
        }()
        let seerrServer = scopedSeerrServer ?? dependencies.restoreSeerrSession()
        if let seerrServer {
            if let seerrUser = try? await dependencies.seerrAuthService.currentUser() {
                appState.setSeerrConnected(server: seerrServer, user: seerrUser)

                // Legacy bridge: if we restored via the global
                // pre-0.3.0 keychain entry (scopedSeerrServer was
                // nil), persist a per-user copy for the active
                // profile so the next profile switch can bring this
                // session back. Without this, pre-0.3.0 Seerr users
                // would have to re-authenticate after every switch.
                if scopedSeerrServer == nil, let uid = activeUserID, let sid = activeServerID {
                    try? dependencies.saveSeerrSession(
                        server: seerrServer,
                        forJellyfinUserID: uid,
                        jellyfinServerID: sid
                    )
                }
            } else {
                // Only forget the profile-scoped entry when it was the
                // one that failed — keeps other profiles' sessions
                // untouched.
                if scopedSeerrServer != nil, let uid = activeUserID, let sid = activeServerID {
                    dependencies.forgetRememberedSeerr(forJellyfinUserID: uid, jellyfinServerID: sid)
                }
                try? dependencies.clearSeerrSession()
            }
        }
    }
}
