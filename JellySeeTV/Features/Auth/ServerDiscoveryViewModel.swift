import Foundation
import Observation

@Observable
final class ServerDiscoveryViewModel {
    var serverAddress = ""
    var isLoading = false
    var errorMessage: String?
    var discoveredServer: JellyfinServer?
    var showLogin = false

    private let discoveryService: ServerDiscoveryServiceProtocol

    init(discoveryService: ServerDiscoveryServiceProtocol) {
        self.discoveryService = discoveryService
    }

    func connectToServer() async {
        guard !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isLoading = true
        errorMessage = nil

        let result = await discoveryService.discoverServer(input: serverAddress)

        switch result {
        case .success(let url, let info):
            discoveredServer = JellyfinServer(
                id: info.id,
                name: info.serverName,
                url: url,
                version: info.version
            )
            showLogin = true
        case .failure(let error):
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
