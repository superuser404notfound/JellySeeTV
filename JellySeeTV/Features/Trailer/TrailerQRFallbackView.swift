import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

/// Full-screen fallback shown when we can't hand the YouTube URL
/// off to an app on the Apple TV (no YouTube app installed, URL
/// scheme not registered, Apple/Google changed the handshake).
/// Presents a large QR code the user can scan with a phone so the
/// trailer at least plays on the nearest screen.
struct TrailerQRFallbackView: View {
    let watchURL: URL
    let title: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Text(String(
                    localized: "trailer.qr.title",
                    defaultValue: "Watch on your phone"
                ))
                .font(.title2)
                .fontWeight(.semibold)

                Text(String(
                    localized: "trailer.qr.subtitle",
                    defaultValue: "Scan this code to open the trailer on a nearby device."
                ))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 700)
            }

            if let image = qrCode(for: watchURL) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 360, height: 360)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(.white)
                    )
            }

            if let title, !title.isEmpty {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Text(watchURL.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

            Button {
                dismiss()
            } label: {
                Text(String(localized: "common.close", defaultValue: "Close"))
                    .font(.body)
                    .fontWeight(.medium)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
            }
            .padding(.top, 12)
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
    }

    private func qrCode(for url: URL) -> UIImage? {
        // CIQRCodeGenerator produces a 1-pixel-per-module bitmap —
        // scale it up with .interpolation(.none) so the modules stay
        // crisp at 360x360 instead of fuzzing into each other.
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
