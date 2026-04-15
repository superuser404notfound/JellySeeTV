import Foundation
import UIKit
import AVFoundation

/// Detects what the connected display can actually handle.
///
/// Uses `AVPlayer.availableHDRModes` for per-format detection (HDR10, DV, HLG).
/// This API is deprecated in tvOS 26 but its replacement (`eligibleForHDRPlayback`)
/// is just a Bool — no way to distinguish DV from HDR10. We need the OptionSet
/// for correct DV metadata handling. Warnings are expected until Apple provides
/// a proper replacement.
@MainActor
enum DisplayCapabilities {

    /// True if the connected display supports any HDR format.
    static var supportsHDR: Bool {
        AVPlayer.eligibleForHDRPlayback
    }

    // MARK: - Per-format detection (availableHDRModes, no tvOS 26 replacement)

    static var supportsDolbyVision: Bool {
        AVPlayer.availableHDRModes.contains(.dolbyVision)
    }

    static var supportsHDR10: Bool {
        AVPlayer.availableHDRModes.contains(.hdr10)
    }

    static var supportsHLG: Bool {
        AVPlayer.availableHDRModes.contains(.hlg)
    }

    /// Display gamut (P3 = wide, sRGB = standard).
    static var displayGamut: UIDisplayGamut {
        UITraitCollection.current.displayGamut
    }

    /// Human-readable summary for debug logs.
    static var summary: String {
        let gamut: String
        switch displayGamut {
        case .P3: gamut = "P3"
        case .SRGB: gamut = "sRGB"
        default: gamut = "unspecified"
        }
        var hdrList: [String] = []
        if supportsHDR10 { hdrList.append("HDR10") }
        if supportsDolbyVision { hdrList.append("DV") }
        if supportsHLG { hdrList.append("HLG") }
        let hdrString = hdrList.isEmpty ? "none" : hdrList.joined(separator: "+")
        return "gamut=\(gamut), HDR=\(hdrString), supportsHDR=\(supportsHDR)"
    }
}
