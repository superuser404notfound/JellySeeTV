import SwiftUI

struct SettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 48) {
                    profileHeader
                    settingsGrid
                    serverInfo
                    logoutButton
                }
                .padding(.vertical, 60)
                .padding(.horizontal, 80)
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 100, height: 100)
                Text(initials)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text(appState.activeUser?.name ?? "")
                .font(.title3)
                .fontWeight(.semibold)

            Text(appState.activeServer?.name ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var initials: String {
        let name = appState.activeUser?.name ?? ""
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // MARK: - Settings Grid

    private var settingsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 24),
            GridItem(.flexible(), spacing: 24),
        ], spacing: 24) {
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
                PlaybackSettingsPlaceholder()
            }
        }
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

    // MARK: - Logout

    private var logoutButton: some View {
        Button(role: .destructive) {
            try? dependencies.clearSession()
            appState.logout()
        } label: {
            Text("settings.logout")
                .font(.subheadline)
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

    var body: some View {
        NavigationLink {
            destination()
                .toolbar(.hidden, for: .tabBar)
        } label: {
            SettingsTileLabel(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(SettingsTileButtonStyle())
    }
}

struct SettingsTileLabel: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 36)
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
}

struct SettingsTileButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFocused ? .white.opacity(0.15) : .white.opacity(0.05))
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.3 : 0), radius: 15, y: 8)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// MARK: - Playback Placeholder

struct PlaybackSettingsPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.circle")
                .font(.system(size: 50))
                .foregroundStyle(.tertiary)
            Text("settings.playback.comingSoon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("settings.playback.title")
    }
}
