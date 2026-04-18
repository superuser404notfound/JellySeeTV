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
            if newValue == .myRequests, let vm = viewModel, vm.myRequests.isEmpty {
                Task { await vm.loadMyRequests() }
            }
        }
    }

    private func bootstrap() {
        guard appState.isSeerrConnected else { return }
        if viewModel == nil {
            let vm = CatalogViewModel(
                discoverService: dependencies.seerrDiscoverService,
                requestService: dependencies.seerrRequestService
            )
            viewModel = vm
            Task { await vm.loadDiscover() }
        }
    }

    private var notConnectedState: some View {
        VStack(spacing: 20) {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

extension SeerrMedia {
    var navigationValue: SeerrMedia { self }
}
