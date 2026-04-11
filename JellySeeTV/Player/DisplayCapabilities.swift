import Foundation
import UIKit

/// Detects what the connected display can actually handle.
///
/// On Apple TV this is used to pick the right Jellyfin DeviceProfile:
/// - HDR-capable display (with Match Dynamic Range on) → permissive
///   profile, AVPlayer direct-streams HDR content with no server work
/// - SDR display, or HDR display with Match Dynamic Range off → the
///   conservative profile that asks the server to tone-map + downscale
///   to 1080p SDR H.264 (which any modest server CPU can handle in
///   real time)
@MainActor
enum DisplayCapabilities {
    /// True if the system reports the connected display as HDR-capable
    /// AND Apple TV is configured (via Match Dynamic Range) to actually
    /// switch into HDR mode when HDR content is presented.
    ///
    /// `maximumPotentialExtendedDynamicRangeColorComponentValue` returns
    /// the highest EDR headroom the screen+system combination can achieve.
    /// Values:
    ///   1.0      → SDR display, OR HDR display with Match Dynamic
    ///              Range turned off (system pretends to be SDR)
    ///   > 1.0    → HDR-capable display, system willing to switch
    ///              into HDR mode for HDR content (typically 1.4-1.6
    ///              for HDR10, up to 4.0+ for Dolby Vision)
    static var supportsHDR: Bool {
        edrHeadroom > 1.0
    }

    /// Display gamut. P3 is wide-gamut and usually goes hand-in-hand with
    /// HDR support, sRGB is the standard SDR gamut.
    static var displayGamut: UIDisplayGamut {
        primaryScreen?.traitCollection.displayGamut ?? .SRGB
    }

    /// The system-reported potential EDR headroom for the connected
    /// display. 1.0 = SDR, > 1.0 = HDR-capable + system willing to
    /// switch.
    static var edrHeadroom: CGFloat {
        guard let screen = primaryScreen else { return 1.0 }
        if #available(tvOS 16.0, iOS 16.0, *) {
            return screen.potentialEDRHeadroom
        }
        return 1.0
    }

    /// Human-readable summary for debug logs.
    static var summary: String {
        let gamut: String
        switch displayGamut {
        case .P3: gamut = "P3"
        case .SRGB: gamut = "sRGB"
        default: gamut = "unspecified"
        }
        return "EDR=\(String(format: "%.2f", edrHeadroom)), gamut=\(gamut), supportsHDR=\(supportsHDR)"
    }

    private static var primaryScreen: UIScreen? {
        // tvOS only ever has one screen and `UIScreen.main` is still the
        // way to get it; the iOS deprecation doesn't apply here.
        UIScreen.main
    }
}
