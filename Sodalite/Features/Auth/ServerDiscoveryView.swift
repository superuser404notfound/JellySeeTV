import SwiftUI

struct ServerDiscoveryView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: ServerDiscoveryViewModel?
    @State private var path = NavigationPath()
    @State private var cloudLoadState: CloudLoadState = .idle

    var addMode: Bool = false
    var onCompletion: (() -> Void)? = nil

    private enum Route: Hashable {
        case login(JellyfinServer)
        case manual
    }

    private enum CloudLoadState: Equatable {
        case idle, loading, nothingFound, noAccount, failed(String?)
    }

    var body: some View {
        ThemeNavigationPathStack(path: $path) {
            VStack(spacing: 32) {
                header

                if let vm = viewModel {
                    switch vm.phase {
                    case .scanning:
                        scanning(vm)
                    case .results:
                        results(vm)
                    case .empty:
                        empty
                    }
                }

                manualButton
                    .padding(.top, 8)

                cloudLoadButton

                if addMode {
                    cancelButton
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(item: Binding(
                get: { viewModel?.pendingTrust },
                set: { viewModel?.pendingTrust = $0 }
            )) { pending in
                CertificateTrustSheet(
                    pending: pending,
                    serverAddress: pending.host,
                    onTrust: {
                        Task {
                            if let resolved = await viewModel?.trustPendingCertificate() {
                                path.append(Route.login(resolved))
                            }
                        }
                    },
                    onCancel: { viewModel?.pendingTrust = nil }
                )
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .login(let server):
                    UserPickerView(server: server, addMode: addMode, onCompletion: onCompletion)
                        .themedNavigationDestination()
                case .manual:
                    ServerAddressEntryView(addMode: addMode, onCompletion: onCompletion)
                        .themedNavigationDestination()
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = ServerDiscoveryViewModel(
                        discovery: dependencies.serverDiscovery,
                        discoveryService: dependencies.serverDiscoveryService,
                        knownServerIDs: Set(dependencies.listKnownServers().map(\.id)),
                        trustStore: dependencies.serverTrustStore
                    )
                }
                await viewModel?.scan()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 24) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
            VStack(spacing: 8) {
                Text("auth.discovery.title")
                    .font(.title2)
                Text("auth.server.subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func scanning(_ vm: ServerDiscoveryViewModel) -> some View {
        VStack(spacing: 16) {
            serverList(vm)
            HStack(spacing: 12) {
                ProgressView()
                Text("auth.discovery.scanning")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func results(_ vm: ServerDiscoveryViewModel) -> some View {
        serverList(vm)
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Text("auth.discovery.empty.title")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            DiagnosticLogLink()
        }
    }

    @ViewBuilder
    private func serverList(_ vm: ServerDiscoveryViewModel) -> some View {
        VStack(spacing: 12) {
            ForEach(vm.servers) { server in
                DiscoveredServerRow(
                    server: server,
                    alreadyAdded: vm.isAlreadyAdded(server),
                    onSelect: {
                        Task {
                            if let resolved = await vm.selectServer(server) {
                                path.append(Route.login(resolved))
                            }
                        }
                    }
                )
            }
        }
        .frame(maxWidth: 760)
    }

    /// The way out of add-mode for somebody who decided not to add a server. This screen is
    /// presented as a full-screen cover, which on iOS dismisses by neither gesture nor chrome, so
    /// until now the only way back to Settings was to finish the flow (Discord report, 2026-08-30).
    /// tvOS has the Menu button, but nothing on screen says so.
    ///
    /// `onCompletion` is what both hosts already use to drop the cover; it means the flow is over,
    /// not that a server arrived.
    private var cancelButton: some View {
        Button {
            onCompletion?()
        } label: {
            Text("common.cancel")
                .font(.body)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
        }
        .buttonStyle(SettingsTileButtonStyle())
    }

    private var manualButton: some View {
        Button {
            path.append(Route.manual)
        } label: {
            Text("auth.discovery.manual")
                .font(.body)
                .fontWeight(.semibold)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
        }
        .buttonStyle(SettingsTileButtonStyle())
    }

    @ViewBuilder
    private var cloudLoadButton: some View {
        VStack(spacing: 8) {
            Button {
                loadFromCloud()
            } label: {
                HStack(spacing: 10) {
                    if cloudLoadState == .loading {
                        ProgressView()
                    }
                    Text("cloudSync.discovery.load")
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
            }
            .buttonStyle(SettingsTileButtonStyle())
            .disabled(cloudLoadState == .loading)

            switch cloudLoadState {
            case .nothingFound:
                Text("cloudSync.discovery.nothingFound")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .noAccount:
                Text("settings.cloudSync.status.noAccount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Text(failureText(message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .idle, .loading:
                EmptyView()
            }
        }
        .padding(.top, 4)
    }

    private func failureText(_ message: String?) -> String {
        guard let message, !message.isEmpty else {
            return String(localized: "cloudSync.discovery.failed", defaultValue: "Could not load from iCloud")
        }
        return String(
            format: String(localized: "cloudSync.discovery.failed %@", defaultValue: "Could not load from iCloud: %@"),
            message
        )
    }

    private func loadFromCloud() {
        guard let cloudSync = dependencies.cloudSync else { return }
        cloudLoadState = .loading
        Task {
            // Reports the real outcome: a fetch that failed, an account that is signed
            // out, and an actually empty zone are three different answers. If data
            // arrived, AppRouter's .cloudSyncDidApplyChanges restore flips the screen.
            switch await cloudSync.loadFromCloud() {
            case .loaded: cloudLoadState = .idle
            case .empty: cloudLoadState = .nothingFound
            case .noAccount: cloudLoadState = .noAccount
            case .failed(let message): cloudLoadState = .failed(message)
            }
        }
    }
}

private struct DiscoveredServerRow: View {
    let server: DiscoveredServer
    let alreadyAdded: Bool
    let onSelect: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(server.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(server.address.host() ?? server.address.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            if alreadyAdded {
                StatusPill("auth.discovery.alreadyAdded")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(focused ? Color.Theme.focusFill : Color.Theme.restFillFaint)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.tint, lineWidth: 3)
                .opacity(focused ? 1 : 0)
        )
        .focusResponse(.row, isFocused: focused)
        .focusable(true)
        .focused($focused)
        .stableTap(isFocused: focused, perform: onSelect)
    }
}
