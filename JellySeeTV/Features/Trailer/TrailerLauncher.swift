import Foundation
import UIKit

/// Hand-off logic for YouTube trailers. tvOS can't embed YouTube
/// natively (no SDK, AVPlayer doesn't understand YouTube streams),
/// but the YouTube TV app registers both a Universal Link for
/// youtu.be and a legacy `youtube://` URL scheme — either should
/// launch the app and deep-link to the specific video.
///
/// Returns the outcome so the caller can react (show a QR-code
/// fallback when the system couldn't open anything).
@MainActor
enum TrailerLauncher {

    enum Outcome: Equatable, Sendable {
        /// The system handed off to the YouTube app (or a browser
        /// on platforms where that exists).
        case openedExternal
        /// No app accepted the URL; caller should present a QR
        /// fallback so the user can scan with a phone.
        case fallbackToQR
    }

    /// Attempts to open a YouTube video externally, trying the
    /// Universal Link first and falling back to the legacy URL
    /// scheme. Both report success synchronously through a
    /// completion handler — `async` bridging keeps the caller
    /// straight-line.
    static func open(_ target: YouTubeURL) async -> Outcome {
        if await open(url: target.watchURL) {
            return .openedExternal
        }
        if let scheme = target.appSchemeURL, await open(url: scheme) {
            return .openedExternal
        }
        return .fallbackToQR
    }

    private static func open(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }
}
