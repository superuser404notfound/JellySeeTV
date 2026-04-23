import SwiftUI

struct SettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 48) {
                    profileHeader
                    settingsList
                    serverInfo
                    logoutButton
                    aboutFooter
                }
                .padding(.vertical, 60)
                .padding(.horizontal, 80)
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            avatar
                .frame(width: 120, height: 120)

            HStack(spacing: 10) {
                Text(appState.activeUser?.name ?? "")
                    .font(.title3)
                    .fontWeight(.semibold)

                if dependencies.storeKitService.isSupporter {
                    Image("PremiumBadge")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel(Text(String(
                            localized: "support.pack.unlocked",
                            defaultValue: "Unlocked"
                        )))
                }
            }

            Text(appState.activeServer?.name ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// User avatar — loads from the Jellyfin server when a
    /// `primaryImageTag` is set, falls back to initials otherwise.
    /// Same treatment as the UserPicker card so the user recognises
    /// themselves consistently across the app.
    @ViewBuilder
    private var avatar: some View {
        if let user = appState.activeUser,
           let url = dependencies.jellyfinImageService.userProfileImageURL(
               userID: user.id,
               tag: user.primaryImageTag
           ) {
            AsyncCachedImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                initialsCircle
            }
            .clipShape(Circle())
        } else {
            initialsCircle
        }
    }

    private var initialsCircle: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Text(initials)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private var initials: String {
        let name = appState.activeUser?.name ?? ""
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Settings List

    private var settingsList: some View {
        // Ordered by how often users actually reach for each tile:
        //   1. Identity       (Profile)
        //   2. Content layout (Home)
        //   3. Media behavior (Playback)
        //   4. Personalisation (Appearance — supporter-gated, lives
        //                       deeper than the always-free tiles)
        //   5. Integrations   (Seerr)
        //   6. Meta / give-back (Support)
        VStack(spacing: 4) {
            SettingsTile(
                icon: "person.2",
                title: "settings.profile.title",
                subtitle: "settings.profile.subtitle"
            ) {
                ProfileSettingsView()
            }

            SettingsTile(
                icon: "square.grid.2x2",
                title: "settings.home.customize",
                subtitle: "settings.home.customizeSubtitle"
            ) {
                HomeCustomizeView()
            }

            SettingsTile(
                icon: "play.circle",
                title: "settings.playback.title",
                subtitle: "settings.playback.subtitle"
            ) {
                PlaybackSettingsView()
            }

            SettingsTile(
                icon: "paintpalette",
                title: "settings.appearance.title",
                subtitle: "settings.appearance.subtitle.short"
            ) {
                AppearanceSettingsView()
            }

            SettingsTile(
                icon: "tray.and.arrow.down",
                title: "settings.seerr.title",
                subtitle: seerrSubtitle
            ) {
                SeerrSettingsView()
            }

            SettingsTile(
                icon: "heart",
                title: "settings.support.title",
                subtitle: "settings.support.subtitle"
            ) {
                SupportDevelopmentView()
            }
        }
    }

    private var seerrSubtitle: LocalizedStringKey {
        appState.isSeerrConnected ? "settings.seerr.subtitle.connected" : "settings.seerr.subtitle.notConnected"
    }

    // MARK: - Server Info

    private var serverInfo: some View {
        HStack(spacing: 40) {
            infoItem(label: "settings.about.version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")

            if let server = appState.activeServer, let version = server.version {
                infoItem(label: "settings.about.serverVersion", value: version)
            }

            if let server = appState.activeServer {
                infoItem(label: "settings.about.serverAddress", value: server.url.host ?? "")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func infoItem(label: LocalizedStringKey, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - About

    /// Brand footer at the very bottom of Settings — the conventional
    /// place for app version and credit. Lives below the logout button
    /// so users see it after they've already navigated past the
    /// actionable content.
    private var aboutFooter: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return VStack(spacing: 12) {
            footerLogo
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
            Text("JellySeeTV \(version) (\(build))")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    @ViewBuilder
    private var footerLogo: some View {
        if dependencies.storeKitService.isSupporter {
            Image("PremiumLogo_Small")
                .resizable()
                .opacity(0.85)
        } else {
            Image("Logo")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Logout

    private var logoutButton: some View {
        // No destructive role — on tvOS that renders as dark red text
        // that's hard to read against the dark background. A subtle
        // arrow-out icon + neutral text is clear enough; the
        // consequence isn't catastrophic.
        Button {
            try? dependencies.clearSession()
            appState.logout()
        } label: {
            Label("settings.logout", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.body)
                .fontWeight(.medium)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .padding(.top, 12)
    }
}

// MARK: - Settings Tile

struct SettingsTile<Destination: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let destination: () -> Destination

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        NavigationLink {
            destination()
                .toolbar(.hidden, for: .tabBar)
        } label: {
            HStack(spacing: 28) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 56, alignment: .center)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
        }
        .buttonStyle(SettingsTileButtonStyle())
    }
}

struct SettingsTileButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFocused ? .white.opacity(0.15) : .white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.tint, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
            .scaleEffect(isFocused ? 1.03 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 15, y: 8)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Playback Placeholder

struct PlaybackSettingsPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.circle")
                .font(.system(size: 50))
                .foregroundStyle(.tertiary)
            Text("settings.playback.comingSoon")
                .foregroundStyle(.secondary)
            Button("home.retry") {
                dismiss()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("settings.playback.title")
        .toolbar(.hidden, for: .tabBar)
    }
}
