import Foundation
import Testing

@testable import Sodalite

/// A refused certificate used to reach the user as "Server unreachable", which is a verdict about
/// the network for a failure that is about identity, and it sent people looking for a fault that was
/// not there. Same shape as `.localNetworkDenied` (#92): the specific case earns its own name.
@Suite("Certificate failure classification")
struct CertificateErrorClassificationTests {

    private final class FakePinStorage: TrustPinStorage, @unchecked Sendable {
        nonisolated func loadPins() -> [String: String] { [:] }
        nonisolated func savePins(_ pins: [String: String]) {}
    }

    private func urlError(_ code: URLError.Code) -> URLError {
        URLError(code)
    }

    @Test("The refusal is read off the top of the error")
    func topLevelCode() {
        #expect(CertificateTrustFailure.code(in: urlError(.serverCertificateUntrusted))
                == NSURLErrorServerCertificateUntrusted)
    }

    @Test("The refusal is read out of the chain when something else sits on top")
    func buriedCode() {
        // The error that tells the truth is rarely the one on top: URLSession hands back a
        // `NSURLErrorSecureConnectionFailed` or a framework wrapper with the real code underneath,
        // which is the same reason the engine's own classifier walks this chain.
        let buried = urlError(.serverCertificateHasUnknownRoot) as NSError
        let middle = NSError(domain: "SomeFrameworkDomain", code: -1,
                             userInfo: [NSUnderlyingErrorKey: buried])
        let top = NSError(domain: "AnotherDomain", code: -99,
                          userInfo: [NSUnderlyingErrorKey: middle])

        #expect(CertificateTrustFailure.code(in: top) == NSURLErrorServerCertificateHasUnknownRoot)
    }

    @Test("Every way a server certificate can be refused counts")
    func allServerCertificateCodes() {
        for code in [
            URLError.Code.serverCertificateUntrusted,
            .serverCertificateHasBadDate,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .secureConnectionFailed,
        ] {
            #expect(CertificateTrustFailure.code(in: urlError(code)) != nil,
                    "\(code) is a refusal the sheet has to be able to answer")
        }
    }

    @Test("A client-certificate demand is a different problem and keeps its own path")
    func clientCertificateIsNotThis() {
        // Trusting the server says nothing about the app being asked to identify itself, and
        // answering that with a trust sheet would offer the user a decision that fixes nothing.
        #expect(CertificateTrustFailure.code(in: urlError(.clientCertificateRejected)) == nil)
        #expect(CertificateTrustFailure.code(in: urlError(.clientCertificateRequired)) == nil)
    }

    @Test("An ordinary transport failure is left alone")
    func unrelatedErrorsAreUntouched() {
        #expect(CertificateTrustFailure.code(in: urlError(.timedOut)) == nil)
        #expect(CertificateTrustFailure.code(in: urlError(.cannotConnectToHost)) == nil)
        #expect(CertificateTrustFailure.code(in: nil) == nil)
    }

    @Test("The failure names the host, and the fingerprint when one was seen")
    func apiErrorCarriesWhatTheSheetNeeds() throws {
        let store = ServerTrustStore(storage: FakePinStorage())
        store.noteRefused("a419", forHost: "media.lan:8920")
        let url = URL(string: "https://media.lan:8920/System/Info/Public")!

        let error = try #require(CertificateTrustFailure.apiError(
            for: urlError(.serverCertificateUntrusted), url: url, store: store))
        guard case .certificateUntrusted(let host, let fingerprint) = error else {
            Issue.record("classified as \(error)")
            return
        }
        #expect(host == "media.lan:8920")
        #expect(fingerprint == "a419")
    }

    @Test("A refusal nobody saw the certificate for is still a refusal")
    func apiErrorWithoutAFingerprint() throws {
        // The handshake can fail before a chain is offered. The sheet then has a host and no
        // fingerprint to show, which is worth saying plainly rather than turning back into
        // "unreachable".
        let store = ServerTrustStore(storage: FakePinStorage())
        let url = URL(string: "https://media.lan:8920/")!

        let error = try #require(CertificateTrustFailure.apiError(
            for: urlError(.secureConnectionFailed), url: url, store: store))
        guard case .certificateUntrusted(_, let fingerprint) = error else {
            Issue.record("classified as \(error)")
            return
        }
        #expect(fingerprint == nil)
    }

    @Test("Anything that is not a certificate refusal is not classified as one")
    func nonCertificateErrorsProduceNothing() {
        let store = ServerTrustStore(storage: FakePinStorage())
        let url = URL(string: "https://media.lan:8920/")!
        #expect(CertificateTrustFailure.apiError(for: urlError(.timedOut), url: url, store: store) == nil)
    }
}
