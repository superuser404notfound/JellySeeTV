import SwiftUI

struct ServerDiscoveryView: View {
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: ServerDiscoveryViewModel?

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                VStack(spacing: 24) {
                    Image("Logo")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)

                    VStack(spacing: 8) {
                        Text("auth.server.title")
                            .font(.title2)

                        Text("auth.server.subtitle")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                if let vm = viewModel {
                    VStack(spacing: 20) {
                        TextField(String(localized: "auth.server.placeholder"), text: Bindable(vm).serverAddress)
                            .textFieldStyle(.automatic)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif

                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            Task { await vm.connectToServer() }
                        } label: {
                            if vm.isLoading {
                                ProgressView()
                            } else {
                                Text("auth.server.connect")
                            }
                        }
                        .disabled(vm.isLoading || vm.serverAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .frame(maxWidth: 500)
                    .navigationDestination(isPresented: Bindable(vm).showLogin) {
                        if let server = vm.discoveredServer {
                            UserPickerView(server: server)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .onAppear {
                if viewModel == nil {
                    viewModel = ServerDiscoveryViewModel(
                        discoveryService: dependencies.serverDiscoveryService
                    )
                }
            }
        }
    }
}
