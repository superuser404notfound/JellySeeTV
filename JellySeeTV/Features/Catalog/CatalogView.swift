import SwiftUI

struct CatalogView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: CatalogViewModel?
    @State private var selectedMedia: SeerrMedia?
    @State private var selectedSection: Section = .discover

    private enum Section: Hashable {
        case discover, myRequests
    }

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isSeerrConnected {
                    notConnectedState
                } else if let vm = viewModel {
                    VStack(spacing: 0) {
                        Picker("", selection: $selectedSection) {
                            Text("catalog.tab.discover").tag(Section.discover)
                            Text("catalog.tab.myRequests").tag(Section.myRequests)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 80)
                        .padding(.top, 20)

                        switch selectedSection {
                        case .discover:
                            CatalogDiscoverView(viewModel: vm) { media in
                                selectedMedia = media
                            }
                        case .myRequests:
                            CatalogMyRequestsView(viewModel: vm)
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationDestination(item: $selectedMedia) { media in
                CatalogDetailView(media: media)
            }
        }
        .onAppear(perform: bootstrap)
        .onChange(of: selectedSection) { _, newValue in
            guard newValue == .myRequests,
                  let vm = viewModel,
                  vm.myRequests.isEmpty,
                  let userID = appState.activeSeerrUser?.id
            else { return }
            Task { await vm.loadMyRequests(userID: userID) }
        }
        .onChange(of: appState.activeUser?.id) { _, _ in
            // Profile switch — the Jellyfin user changed, so any
            // cached Seerr state (discover sections tied to the old
            // account's permissions, My Requests cached for the
            // previous Seerr user) is stale. Reset the view model so
            // bootstrap() rebuilds it once Seerr is reconnected for
            // the new profile.
            viewModel = nil
            selectedMedia = nil
            selectedSection = .discover
        }
        .onChange(of: appState.isSeerrConnected) { _, connected in
            // Seerr just came online (initial setup or post-switch
            // re-auth). .onAppear already ran when the tab first
            // mounted and bailed out of bootstrap because there was
            // no connection yet, so nothing else would kick the load
            // without this trigger — the user saw an endless spinner
            // until they tab-hopped away and back.
            if connected {
                bootstrap()
            } else {
                viewModel = nil
                selectedMedia = nil
                selectedSection = .discover
            }
        }
    }

    private func bootstrap() {
        guard appState.isSeerrConnected else { return }
        if viewModel == nil {
            let vm = CatalogViewModel(
                discoverService: dependencies.seerrDiscoverService,
                requestService: dependencies.seerrRequestService,
                mediaService: dependencies.seerrMediaService
            )
            viewModel = vm
            Task { await vm.loadDiscover() }
        }
    }

    private var notConnectedState: some View {
        VStack(spacing: 24) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("catalog.empty.noServer.title")
                .font(.headline)
            Text("catalog.empty.noServer.description")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)

            // Quick-jump into the Seerr setup flow so first-time
            // users aren't left staring at an empty state with no
            // obvious path forward. Pushed inside the Catalog's own
            // NavigationStack — tapping back returns to the tab.
            NavigationLink {
                SeerrSettingsView()
                    .toolbar(.hidden, for: .tabBar)
            } label: {
                Label {
                    Text(String(
                        localized: "catalog.empty.noServer.setup",
                        defaultValue: "Set up Seerr"
                    ))
                } icon: {
                    Image(systemName: "arrow.right.circle")
                }
                .font(.body)
                .fontWeight(.medium)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

extension SeerrMedia {
    var navigationValue: SeerrMedia { self }
}
