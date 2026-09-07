import Foundation
import Observation

/// A certificate the user has been asked about and not yet answered for.
struct PendingCertificateTrust: Identifiable, Equatable {
    let host: String
    /// Nil when the handshake failed before a chain was offered, so there is nothing to compare.
    let fingerprint: String?
    /// This host was trusted before, with a different certificate. A first acceptance and a change
    /// are not the same question: one of them can be an attack, and they must not read alike.
    let isReplacingAPin: Bool

    var id: String { host + (fingerprint ?? "") }
}

@Observable
final class ServerAddressEntryViewModel {
    var serverAddress = ""
    var isLoading = false
    var errorMessage: String?
    var discoveredServer: JellyfinServer?
    var showLogin = false
    /// Set instead of `errorMessage` for a certificate refusal, because that is the one connection
    /// failure on this screen the user can actually answer.
    var pendingTrust: PendingCertificateTrust?

    private let discoveryService: ServerDiscoveryServiceProtocol
    private let trustStore: ServerTrustStore

    init(discoveryService: ServerDiscoveryServiceProtocol, trustStore: ServerTrustStore) {
        self.discoveryService = discoveryService
        self.trustStore = trustStore
    }

    func connectToServer() async {
        guard !serverAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isLoading = true
        errorMessage = nil
        pendingTrust = nil

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
        case .failure(.certificateUntrusted(let host, let fingerprint)):
            pendingTrust = PendingCertificateTrust(
                host: host,
                fingerprint: fingerprint,
                isReplacingAPin: trustStore.pinnedFingerprint(forHost: host) != nil)
        case .failure(let error):
            errorMessage = ErrorText.user(for: error)
        }

        isLoading = false
    }

    /// Records the answer and acts on it. Storing the pin without retrying would leave the user on a
    /// screen that still says no to an address they just said yes to.
    func trustPendingCertificate() async {
        guard let pending = pendingTrust, let fingerprint = pending.fingerprint else {
            pendingTrust = nil
            return
        }
        trustStore.pin(fingerprint, forHost: pending.host)
        pendingTrust = nil
        await connectToServer()
    }
}
