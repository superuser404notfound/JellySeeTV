import SwiftUI

struct SeerrStatusBadge: View {
    let status: SeerrMediaStatus
    var compact: Bool = false

    var body: some View {
        if compact {
            Image(systemName: status.systemImage)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(6)
                .background(color, in: Circle())
        } else {
            Label {
                Text(LocalizedStringKey(status.localizationKey))
                    .font(.caption)
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: status.systemImage)
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
        }
    }

    private var color: Color {
        switch status {
        case .unknown: .gray
        case .pending: .orange
        case .processing: .blue
        case .partiallyAvailable: .teal
        case .available: .green
        }
    }
}

struct SeerrRequestStatusBadge: View {
    let status: SeerrRequestStatus

    var body: some View {
        Label {
            Text(LocalizedStringKey(status.localizationKey))
                .font(.caption)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: systemImage)
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color, in: Capsule())
    }

    private var systemImage: String {
        switch status {
        case .pendingApproval: "clock"
        case .approved: "checkmark"
        case .declined: "xmark"
        }
    }

    private var color: Color {
        switch status {
        case .pendingApproval: .orange
        case .approved: .green
        case .declined: .red
        }
    }
}
