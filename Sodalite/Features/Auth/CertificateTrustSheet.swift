import SwiftUI

/// The one place this app asks whether a server may be believed about who it is.
///
/// It shows the fingerprint rather than only asking, because the fingerprint is the only thing that
/// makes the answer worth anything: a user who can compare it against what their own server prints
/// is deciding, and one who cannot is at least being told what they are accepting. Nothing here
/// offers to turn the question off for everything, which is the version of this dialog that trains
/// people to press yes.
struct CertificateTrustSheet: View {
    let pending: PendingCertificateTrust
    let serverAddress: String
    let onTrust: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text(pending.isReplacingAPin
                     ? "certificateTrust.title.changed"
                     : "certificateTrust.title")
                    .font(.title2)
                    .multilineTextAlignment(.center)

                Text(pending.isReplacingAPin
                     ? "certificateTrust.body.changed"
                     : "certificateTrust.body")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(serverAddress)
                    .font(.callout)
                    .fontWeight(.semibold)

                if let fingerprint = pending.fingerprint {
                    Text("certificateTrust.fingerprintLabel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Wrapping, not truncating: a fingerprint with its middle missing cannot be
                    // compared against anything, which is the only reason it is on screen.
                    Text(CertificateFingerprint.grouped(fingerprint))
                        .font(.system(.footnote, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("certificateTrust.noFingerprint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.Theme.restFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.Theme.panelEdge, lineWidth: 1)
            )

            VStack(spacing: 12) {
                // Only offered when there is a certificate to accept. A refusal with nothing to show
                // has nothing to pin, and a button that pins nothing is a button that lies.
                if pending.fingerprint != nil {
                    Button(action: onTrust) {
                        Text("certificateTrust.trustButton")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(SettingsTileButtonStyle(isProminent: true))
                }
                Button(action: onCancel) {
                    Text("common.cancel")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(SettingsTileButtonStyle())
            }
        }
        .padding(40)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.Theme.surface)
    }
}
