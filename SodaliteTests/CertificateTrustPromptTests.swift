import Foundation
import Testing

@testable import Sodalite

/// The decision the user is asked for, and the one place it is asked.
///
/// A certificate refusal is the only connection failure in this app that the user can actually do
/// something about, so it must not land in the error line beside the ones they cannot. It raises a
/// sheet instead, and the sheet has to be able to say which certificate it is talking about.
@MainActor
@Suite("Certificate trust prompt")
struct CertificateTrustPromptTests {

    private final class FakePinStorage: TrustPinStorage, @unchecked Sendable {
        private let lock = NSLock()
        private var pins: [String: String]
        init(_ pins: [String: String] = [:]) { self.pins = pins }
        nonisolated func loadPins() -> [String: String] { lock.lock(); defer { lock.unlock() }; return pins }
        nonisolated func savePins(_ pins: [String: String]) { lock.lock(); self.pins = pins; lock.unlock() }
    }

    private final class ScriptedDiscovery: ServerDiscoveryServiceProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var outcomes: [ServerDiscoveryResult]
        private(set) var calls = 0

        init(_ outcomes: [ServerDiscoveryResult]) { self.outcomes = outcomes }

        nonisolated func discoverServer(input: String) async -> ServerDiscoveryResult {
            next()
        }

        private func next() -> ServerDiscoveryResult {
            lock.lock(); defer { lock.unlock() }
            calls += 1
            return outcomes.isEmpty ? .failure(.serverUnreachable) : outcomes.removeFirst()
        }
    }

    private static func serverInfo() -> ServerDiscoveryInfo {
        ServerDiscoveryInfo(id: "srv", serverName: "Media", version: "10.10.0")
    }

    @Test("A certificate refusal asks rather than complains")
    func refusalRaisesTheSheet() async {
        let store = ServerTrustStore(storage: FakePinStorage())
        let model = ServerAddressEntryViewModel(
            discoveryService: ScriptedDiscovery([
                .failure(.certificateUntrusted(host: "media.lan:8920", fingerprint: "a419"))
            ]),
            trustStore: store)
        model.serverAddress = "https://media.lan:8920"

        await model.connectToServer()

        #expect(model.pendingTrust?.host == "media.lan:8920")
        #expect(model.pendingTrust?.fingerprint == "a419")
        #expect(model.errorMessage == nil,
                "the error line would put an answerable question where nothing can be answered")
    }

    @Test("Every other failure stays in the error line")
    func otherFailuresAreUnchanged() async {
        let model = ServerAddressEntryViewModel(
            discoveryService: ScriptedDiscovery([.failure(.serverUnreachable)]),
            trustStore: ServerTrustStore(storage: FakePinStorage()))
        model.serverAddress = "https://media.lan:8920"

        await model.connectToServer()

        #expect(model.pendingTrust == nil)
        #expect(model.errorMessage != nil)
    }

    @Test("Accepting pins the certificate and asks the server again")
    func acceptingRetries() async {
        let store = ServerTrustStore(storage: FakePinStorage())
        let discovery = ScriptedDiscovery([
            .failure(.certificateUntrusted(host: "media.lan:8920", fingerprint: "a419")),
            .success(url: URL(string: "https://media.lan:8920")!, serverInfo: Self.serverInfo()),
        ])
        let model = ServerAddressEntryViewModel(discoveryService: discovery, trustStore: store)
        model.serverAddress = "https://media.lan:8920"
        await model.connectToServer()

        await model.trustPendingCertificate()

        #expect(store.pinnedFingerprint(forHost: "media.lan:8920") == "a419")
        #expect(discovery.calls == 2, "the answer has to be acted on, not just stored")
        #expect(model.pendingTrust == nil)
        #expect(model.discoveredServer?.id == "srv")
        #expect(model.showLogin)
    }

    @Test("A host that was already trusted with a different certificate says so")
    func changedCertificateIsItsOwnQuestion() async {
        // The first time is a question about a server. The second time is a question about a
        // change, and the two must not read the same: one of them can be an attack.
        let store = ServerTrustStore(storage: FakePinStorage(["media.lan:8920": "0000"]))
        let model = ServerAddressEntryViewModel(
            discoveryService: ScriptedDiscovery([
                .failure(.certificateUntrusted(host: "media.lan:8920", fingerprint: "a419"))
            ]),
            trustStore: store)
        model.serverAddress = "https://media.lan:8920"

        await model.connectToServer()

        #expect(model.pendingTrust?.isReplacingAPin == true)
    }

    @Test("A refusal with no certificate to show still asks")
    func refusalWithoutFingerprint() async {
        // The handshake can fail before a chain is offered. There is nothing to compare then, and
        // saying so is better than turning it back into an unreachable server.
        let model = ServerAddressEntryViewModel(
            discoveryService: ScriptedDiscovery([
                .failure(.certificateUntrusted(host: "media.lan:8920", fingerprint: nil))
            ]),
            trustStore: ServerTrustStore(storage: FakePinStorage()))
        model.serverAddress = "https://media.lan:8920"

        await model.connectToServer()

        #expect(model.pendingTrust?.fingerprint == nil)
        #expect(model.pendingTrust?.host == "media.lan:8920")
    }

    @Test("Nothing is pinned by a sheet that was dismissed")
    func dismissingPinsNothing() async {
        let store = ServerTrustStore(storage: FakePinStorage())
        let model = ServerAddressEntryViewModel(
            discoveryService: ScriptedDiscovery([
                .failure(.certificateUntrusted(host: "media.lan:8920", fingerprint: "a419"))
            ]),
            trustStore: store)
        model.serverAddress = "https://media.lan:8920"
        await model.connectToServer()

        model.pendingTrust = nil

        #expect(store.pinnedFingerprint(forHost: "media.lan:8920") == nil)
    }
}
