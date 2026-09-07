import Foundation

/// Reads "this server's certificate was refused" out of a transport error.
///
/// Without it the failure folds into `.serverUnreachable`, which is a verdict about the network for
/// something that is about identity, and the user goes looking for a fault that is not there. The
/// same reasoning produced `APIError.localNetworkDenied` (#92) and, on the engine side,
/// `PlaybackErrorKind.sourceCertificateRejected`.
nonisolated enum CertificateTrustFailure {

    /// The refusals a trust decision can answer. Client-certificate codes are deliberately absent:
    /// being asked to identify ourselves is a different problem, and offering a trust sheet for it
    /// would hand the user a decision that fixes nothing.
    private static let codes: Set<Int> = [
        NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasBadDate,
        NSURLErrorServerCertificateHasUnknownRoot,
        NSURLErrorServerCertificateNotYetValid,
        NSURLErrorSecureConnectionFailed,
    ]

    /// The NSURLError code, found by walking `NSUnderlyingErrorKey` rather than only reading the
    /// top. The error that says what happened is rarely the one on top: URLSession wraps, and so do
    /// the layers above it.
    static func code(in error: Error?) -> Int? {
        var current = error as NSError?
        var depth = 0
        while let error = current, depth < 8 {
            if error.domain == NSURLErrorDomain, codes.contains(error.code) {
                return error.code
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return nil
    }

    /// The failure as the server flow needs it: which host refused, and which certificate it offered
    /// when the handshake got far enough for one to be seen. Nil when this was not a certificate
    /// refusal at all, so the caller's existing classification stands.
    static func apiError(for error: Error?, url: URL?, store: ServerTrustStore) -> APIError? {
        guard code(in: error) != nil else { return nil }
        guard let url, let host = ServerTrustStore.hostKey(for: url) else { return nil }
        return .certificateUntrusted(host: host, fingerprint: store.refusedFingerprint(forHost: host))
    }
}
