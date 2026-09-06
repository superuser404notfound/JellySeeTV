import Testing
import Foundation
@testable import Sodalite

@MainActor
struct ServerDiscoveryViewModelTests {

    /// Nothing is pinned in these tests; the store is here because the view model needs one to ask
    /// whether a refusal is a change.
    private final class NoPinStorage: TrustPinStorage, @unchecked Sendable {
        nonisolated func loadPins() -> [String: String] { [:] }
        nonisolated func savePins(_ pins: [String: String]) {}
    }

    private struct FakeDiscovery: JellyfinServerDiscoveryProtocol {
        let yields: [DiscoveredServer]
        func discover() -> AsyncStream<DiscoveredServer> {
            AsyncStream { c in
                for s in yields { c.yield(s) }
                c.finish()
            }
        }
    }

    private struct FakeProbe: ServerDiscoveryServiceProtocol {
        func discoverServer(input: String) async -> ServerDiscoveryResult {
            .failure(.serverUnreachable)
        }
    }

    private func server(_ id: String) -> DiscoveredServer {
        DiscoveredServer(id: id, name: "S-\(id)", address: URL(string: "http://10.0.0.1:8096")!)
    }

    @Test func emptyStream_endsInEmptyPhase() async {
        let vm = ServerDiscoveryViewModel(
            discovery: FakeDiscovery(yields: []),
            discoveryService: FakeProbe(),
            knownServerIDs: [],
            trustStore: ServerTrustStore(storage: NoPinStorage())
        )
        await vm.scan()
        #expect(vm.phase == .empty)
        #expect(vm.servers.isEmpty)
    }

    @Test func distinctServers_appearInResults() async {
        let vm = ServerDiscoveryViewModel(
            discovery: FakeDiscovery(yields: [server("a"), server("b")]),
            discoveryService: FakeProbe(),
            knownServerIDs: [],
            trustStore: ServerTrustStore(storage: NoPinStorage())
        )
        await vm.scan()
        #expect(vm.phase == .results)
        #expect(vm.servers.map(\.id) == ["a", "b"])
    }

    @Test func duplicateIDs_areDeduped() async {
        let vm = ServerDiscoveryViewModel(
            discovery: FakeDiscovery(yields: [server("a"), server("a")]),
            discoveryService: FakeProbe(),
            knownServerIDs: [],
            trustStore: ServerTrustStore(storage: NoPinStorage())
        )
        await vm.scan()
        #expect(vm.servers.count == 1)
    }

    @Test func isAlreadyAdded_reflectsKnownServerIDs() async {
        let vm = ServerDiscoveryViewModel(
            discovery: FakeDiscovery(yields: []),
            discoveryService: FakeProbe(),
            knownServerIDs: ["a"],
            trustStore: ServerTrustStore(storage: NoPinStorage())
        )
        #expect(vm.isAlreadyAdded(server("a")))
        #expect(!vm.isAlreadyAdded(server("b")))
    }
}
