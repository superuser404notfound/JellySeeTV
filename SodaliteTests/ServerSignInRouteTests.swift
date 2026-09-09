import Foundation
import Testing
@testable import Sodalite

/// Signing in runs before there is an active server, and route resolution only ever covered the
/// active one. So the whole sign-in flow ran on `preferredURL(for:)`: the last route that worked,
/// else the internal slot. Somebody whose last session was at home therefore signed in against a
/// LAN address from a phone on cellular, and the symptom is that signing in works at home and
/// nowhere else, while the very same server answers fine in a browser.
@Suite("Signing in probes both addresses", .serialized)
@MainActor
struct ServerSignInRouteTests {
    private let serverID = "srv-signin"
    private let internalURL = URL(string: "http://10.0.0.2:8096")!
    private let externalURL = URL(string: "https://jf.example.com")!

    private func container(answering reachable: Set<URL>) throws -> DependencyContainer {
        let container = DependencyContainer(
            keychainService: InMemoryKeychain(),
            defaults: UserDefaults(suiteName: "signin-route-\(UUID().uuidString)")!
        )
        try container.addServer(JellyfinServer(
            id: serverID, name: "Home", internalURL: internalURL, externalURL: externalURL
        ))
        container.jellyfinProbe = { url in reachable.contains(url) }
        return container
    }

    /// The reporter's case: last session was at home, this one is on cellular.
    @Test func awayFromHomeTheExternalAddressWins() async throws {
        let container = try container(answering: [externalURL])
        container.serverRouteStore.setLastRoute(.internal, serverID: serverID)
        let server = try #require(container.listKnownServers().first)

        let resolved = await container.resolveSignInRoute(for: server)

        #expect(resolved == externalURL)
        #expect(container.jellyfinClient.baseURL == externalURL)
    }

    /// At home the LAN address still wins, so the fix does not push every sign-in through the proxy.
    @Test func atHomeTheInternalAddressStillWins() async throws {
        let container = try container(answering: [internalURL, externalURL])
        container.serverRouteStore.setLastRoute(.external, serverID: serverID)
        let server = try #require(container.listKnownServers().first)

        let resolved = await container.resolveSignInRoute(for: server)

        #expect(resolved == internalURL)
        #expect(container.jellyfinClient.baseURL == internalURL)
    }

    /// The route learned here is what the session that follows starts on, so it has to be recorded.
    @Test func theResolvedRouteIsRemembered() async throws {
        let container = try container(answering: [externalURL])
        let server = try #require(container.listKnownServers().first)

        await container.resolveSignInRoute(for: server)

        #expect(container.serverRouteStore.lastRoute(serverID: serverID) == .external)
    }

    /// Nothing answers: the sign-in still needs an address to fail against and report, rather than
    /// being left pointing at nothing.
    @Test func anUnreachableServerStillGetsAnAddress() async throws {
        let container = try container(answering: [])
        container.serverRouteStore.setLastRoute(.external, serverID: serverID)
        let server = try #require(container.listKnownServers().first)

        let resolved = await container.resolveSignInRoute(for: server)

        #expect(resolved == externalURL)
    }
}
