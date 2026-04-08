import SwiftUI

struct SettingsView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        NavigationStack {
            List {
                accountSection
                homeSection
                playbackSection
                aboutSection
                logoutSection
            }
            .navigationTitle("tab.settings")
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.activeUser?.name ?? "")
                        .font(.body)
                    Text(appState.activeServer?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("settings.section.account", systemImage: "person")
        }
    }

    // MARK: - Home

    private var homeSection: some View {
        Section {
            NavigationLink {
                HomeCustomizeView()
            } label: {
                Label("settings.home.customize", systemImage: "square.grid.2x2")
            }
        } header: {
            Label("settings.section.home", systemImage: "house")
        }
    }

    // MARK: - Playback (placeholder for Phase 3)

    private var playbackSection: some View {
        Section {
            NavigationLink {
                Text("settings.playback.comingSoon")
                    .foregroundStyle(.secondary)
            } label: {
                Label("settings.playback.title", systemImage: "play.circle")
            }
        } header: {
            Label("settings.section.playback", systemImage: "play.rectangle")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("settings.about.version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }

            if let server = appState.activeServer, let version = server.version {
                HStack {
                    Text("settings.about.serverVersion")
                    Spacer()
                    Text(version)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("settings.section.about", systemImage: "info.circle")
        }
    }

    // MARK: - Logout

    private var logoutSection: some View {
        Section {
            Button(role: .destructive) {
                try? dependencies.clearSession()
                appState.logout()
            } label: {
                HStack {
                    Spacer()
                    Text("settings.logout")
                    Spacer()
                }
            }
        }
    }
}
