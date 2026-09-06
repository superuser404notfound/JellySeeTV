import Foundation
import Security
import Testing

@testable import Sodalite

/// The policy every session in this app answers a server-trust challenge with.
///
/// `URLProtectionSpace` cannot be constructed carrying a `serverTrust`, so a test built on a
/// synthesized challenge can only ever reach the nil arm. The decision therefore takes the trust
/// object as an argument and the delegate is the thin part that pulls it off the challenge, which is
/// what lets the pinned-match arm be tested at all.
@Suite("Server trust decision")
struct ServerTrustDelegateTests {

    private final class FakePinStorage: TrustPinStorage, @unchecked Sendable {
        private let lock = NSLock()
        private var pins: [String: String]
        init(_ pins: [String: String] = [:]) { self.pins = pins }
        nonisolated func loadPins() -> [String: String] { lock.lock(); defer { lock.unlock() }; return pins }
        nonisolated func savePins(_ pins: [String: String]) { lock.lock(); self.pins = pins; lock.unlock() }
    }

    private static func certificate(_ base64: String) throws -> SecCertificate {
        let der = try #require(Data(base64Encoded: base64.filter { !$0.isWhitespace }))
        return try #require(SecCertificateCreateWithData(nil, der as CFData))
    }

    private static func trust(_ certificate: SecCertificate) throws -> SecTrust {
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            certificate, SecPolicyCreateBasicX509(), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    private func decide(
        store: ServerTrustStore,
        trust: SecTrust?,
        method: String = NSURLAuthenticationMethodServerTrust,
        host: String = "media.lan",
        port: Int = 8920
    ) -> ServerTrustDecision {
        ServerTrustDelegate.decide(
            host: host, port: port, authenticationMethod: method, serverTrust: trust, store: store)
    }

    @Test("The certificate the user accepted is the one that gets in")
    func pinnedLeafIsAccepted() throws {
        let certificate = try Self.certificate(Self.mediaLanDER)
        let store = ServerTrustStore(
            storage: FakePinStorage(["media.lan:8920": CertificateFingerprint.sha256(of: certificate)]))

        #expect(decide(store: store, trust: try Self.trust(certificate)) == .useCredential)
    }

    @Test("A different certificate on a pinned host is not the pinned one")
    func changedLeafFallsBackToTheSystem() throws {
        let pinned = try Self.certificate(Self.mediaLanDER)
        let offered = try Self.certificate(Self.otherLanDER)
        let store = ServerTrustStore(
            storage: FakePinStorage(["media.lan:8920": CertificateFingerprint.sha256(of: pinned)]))

        // Default handling, not a refusal of our own: a host that has since got a real certificate
        // must keep working, and one that has not will fail on the system's verdict as it always did.
        #expect(decide(store: store, trust: try Self.trust(offered)) == .defaultHandling)
        #expect(store.refusedFingerprint(forHost: "media.lan:8920")
                == CertificateFingerprint.sha256(of: offered),
                "the certificate that was actually offered has to be showable")
    }

    @Test("An unpinned host is left to the system, and what it offered is remembered")
    func unpinnedHostRecordsWhatItOffered() throws {
        let offered = try Self.certificate(Self.mediaLanDER)
        let store = ServerTrustStore(storage: FakePinStorage())

        #expect(decide(store: store, trust: try Self.trust(offered)) == .defaultHandling)
        #expect(store.refusedFingerprint(forHost: "media.lan:8920")
                == CertificateFingerprint.sha256(of: offered))
    }

    @Test("Nothing but a server-trust challenge is this policy's business")
    func otherChallengesAreUntouched() throws {
        let certificate = try Self.certificate(Self.mediaLanDER)
        let store = ServerTrustStore(
            storage: FakePinStorage(["media.lan:8920": CertificateFingerprint.sha256(of: certificate)]))

        // HTTP auth and client certificates go to default handling with the pin unread, so this
        // cannot become the reason a password prompt behaves differently.
        #expect(decide(store: store, trust: try Self.trust(certificate),
                       method: NSURLAuthenticationMethodHTTPBasic) == .defaultHandling)
        #expect(decide(store: store, trust: try Self.trust(certificate),
                       method: NSURLAuthenticationMethodClientCertificate) == .defaultHandling)
    }

    @Test("A challenge with no trust object cannot be answered from a pin")
    func missingTrustObjectFallsThrough() {
        let store = ServerTrustStore(storage: FakePinStorage(["media.lan:8920": "a419"]))
        #expect(decide(store: store, trust: SecTrust?.none) == .defaultHandling)
    }

    @Test("The pin belongs to the host that was pinned")
    func pinDoesNotTravel() throws {
        let certificate = try Self.certificate(Self.mediaLanDER)
        let store = ServerTrustStore(
            storage: FakePinStorage(["media.lan:8920": CertificateFingerprint.sha256(of: certificate)]))

        #expect(decide(store: store, trust: try Self.trust(certificate),
                       host: "media.example.com", port: 443) == .defaultHandling)
    }

    /// A self-signed certificate for media.lan, generated for this suite. Its only job is to be a
    /// real `SecCertificate`, so the pinned-match arm is exercised rather than only the nil arm.
    static let mediaLanDER = """
            MIICpDCCAYwCCQDmnh2+PkwodjANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAltZWRpYS5sYW4w
            HhcNMjYwOTA2MjA0MzI0WhcNNDYwOTAxMjA0MzI0WjAUMRIwEAYDVQQDDAltZWRpYS5sYW4wggEi
            MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC8kVgzYeXDMG274wfCxYATp4Y7d6E+/wl6weX8
            PgOAkUk/EjWGKAtDFO09TPboKgrwCMSIcD2cXP04JcxcPi+ktDwJW0Gqr2XXOAcBOWBb6RLdIks0
            tN7Z+/K8qrOAGGawBnpZ2wjX6XhZJ1vXre5dEGkH8Z4cYYj61NXZvK7ZtpLUvQxHVHCUpf+Aork/
            hSApSBwMVDMABz9rwlI3SEqhF+3237h7fEtAxkfaG7oVzG/NIFo3MMbzbdzTeCiwehDA1dp5BvZ+
            GUQB5j8v5vhBZuQPE0Xh30uXhMKXoLuDhxxu+PfQGDFH2R0VKLlXiV3B3EPIn44AZCKVrvasBaIN
            AgMBAAEwDQYJKoZIhvcNAQELBQADggEBAHNpUmLaSY4kX4S4HqpK/Uhi0Wcw3PGY+3yN2ckz83jY
            UpPCJCs8+WnRbzNtr5orfhxIlgpvCWT2Z3p8qzTisEvpp1+UE8u93uF8iP+9UPEmvIz6hA6ViT1o
            MQNrd7dMTLVxx48RXB1tRqHA/VFX9cWibyM2AkuxPp8s1ui9u0SpC8oVtn3DIgntJq+40LRLVTrZ
            h7xMZ3HJQq7ADGs/hO9G4K52zZSyPmk2kcaEWgeLwHGObs0dIv+SHMljEiJN8nCWMF8gLBHzoU8Z
            0LXy+OmeKV43xWR+6Jc1rr1LpQmbjHEHRMlqbbL+smtMTCZ+QBVu1KTDbmydjhV7Xb1Rqcg=
            """

    /// A second, different one. Same shape, different bytes, which is the whole point.
    static let otherLanDER = """
            MIICpDCCAYwCCQCzJ7tzvcWeETANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAlvdGhlci5sYW4w
            HhcNMjYwOTA2MjA0MzI0WhcNNDYwOTAxMjA0MzI0WjAUMRIwEAYDVQQDDAlvdGhlci5sYW4wggEi
            MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC2rk7b9B3VpNRbYrOVoA1IoKgoAFiS82JN0Nx7
            ok6dJA9kdZnAXfNVzfHODw3PAb7HsvFUhe8lOocY9kiYdDhRUiPZKOAp948H4TdTMsmeT6yUlLI/
            b7JznxkGm26WdNhPtVvZMkS+WTPB1OK4S0B5hHy3O3ebfF9UNS9r2AWbRX9QXdoz5nXFhlxrtgUj
            QQV9Y+3tD6bbxigVK6bXjFtRsDks5fSSpSalIUYoNT8pfdRllrOCoJDtTLTX8fQ/Lb9tPG36+u2g
            fSA08dTk8xd5cMEUPkocSvoCQX+pVXNl3WqobP58o97wfI28AuBpvu4nEpqczRqH7KVCjbWHpODb
            AgMBAAEwDQYJKoZIhvcNAQELBQADggEBAHnBOWV1CK/KJUnOx/y8KrYYnb9CQDhonOen1tTkzn4z
            L9TKYzM8D9S/XIs9znqNaJRI4hSNFSh4ZDXH9Yfn3rxo6jBJqpRV9P7fiiJ97cZJ/V41Fr03MSHs
            5+WoT/O0F2qxpbFEXxHe1LHUZuUbXu3gN99CyUUS/59wh+UCU8SLnRZd7rT3i2gj+c1a2+dvYN1+
            jY5lkRlIUaZrYeNCgqJlQ+yEIznCFPddVqSa9fxnBfzSQYPP1Bkpxr3KuGIMuxX+E8S5Gi2ib3Xw
            rEalspzTztj3MbteMTkP+xZIrzbZDcUuhTJq6fHWvvmnJ+uO3jpsUVDsuM88pTE39+vqWC4=
            """
}
