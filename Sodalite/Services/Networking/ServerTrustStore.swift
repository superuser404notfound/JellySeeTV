import CryptoKit
import Foundation
import Security

/// The SHA-256 of a certificate, in the two forms this app needs it: one to compare, one to read.
enum CertificateFingerprint {

    /// Lowercase hex of the DER SHA-256. The whole certificate rather than its public key: what the
    /// user was shown and accepted is this exact certificate, and a renewal that keeps the key is
    /// still a new certificate the user has not seen.
    static func sha256(of certificate: SecCertificate) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    /// The leaf of a trust object, which is the certificate the origin is presenting as itself.
    static func sha256(ofLeafIn trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first
        else { return nil }
        return sha256(of: leaf)
    }

    /// Uppercase colon-separated byte pairs. Nobody reads 64 hex characters as one run, and the
    /// point of showing a fingerprint at all is that it can be held against what a server's own
    /// admin page says.
    static func grouped(_ hex: String) -> String {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: min(2, hex.count - offset))
            return hex[start..<end].uppercased()
        }.joined(separator: ":")
    }
}

/// Where the pins live. Fronted so the store can be tested without a keychain, and so the keychain
/// half stays with `DependencyContainer` like every other credential in this app.
protocol TrustPinStorage: Sendable {
    func loadPins() -> [String: String]
    func savePins(_ pins: [String: String])
}

/// Which server certificates this device has been told to accept, keyed by the host that offered
/// them.
///
/// Per host and not per server: a `JellyfinServer` carries a LAN and a WAN address, and typically
/// only the first is behind a private certificate. Trusting the server as a whole would quietly
/// lower the bar for the address that has a real certificate, which is the one an attacker would
/// have to be on the path of.
///
/// The fingerprint is the decision. An entry does not say "this host may present anything", it says
/// "this host may present THIS certificate", so a different one later is a question the user gets
/// asked again rather than an answer they already gave.
final class ServerTrustStore: @unchecked Sendable {

    private let storage: any TrustPinStorage
    private let lock = NSLock()
    private var pins: [String: String]
    /// What was offered and not accepted, so the sheet can show a fingerprint the user has not
    /// trusted yet. In memory only: a certificate the app merely saw must not read, after a
    /// relaunch, like one it was told about.
    private var refusals: [String: String] = [:]

    init(storage: any TrustPinStorage) {
        self.storage = storage
        self.pins = storage.loadPins()
    }

    /// `host:port`, which is the granularity a certificate is offered at. The port comes from the
    /// scheme when the URL omits it, so the address the user typed and the challenge the connection
    /// raises name the same host.
    static func hostKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return nil
        }
        let port = url.port ?? (scheme == "http" ? 80 : scheme == "https" ? 443 : nil)
        guard let port else { return nil }
        return "\(host):\(port)"
    }

    static func hostKey(host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }

    func pinnedFingerprint(forHost host: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return pins[host]
    }

    /// Records the decision and writes it through at once. A pin that only reached memory would ask
    /// the user again on the next launch, which teaches them to accept the sheet without reading it.
    func pin(_ fingerprint: String, forHost host: String) {
        lock.lock()
        pins[host] = fingerprint
        refusals[host] = nil
        let snapshot = pins
        lock.unlock()
        storage.savePins(snapshot)
    }

    func noteRefused(_ fingerprint: String, forHost host: String) {
        lock.lock()
        refusals[host] = fingerprint
        lock.unlock()
    }

    func refusedFingerprint(forHost host: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return refusals[host]
    }
}
