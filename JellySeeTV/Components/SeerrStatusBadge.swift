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
        case .failed: "exclamationmark.triangle"
        case .completed: "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .pendingApproval: .orange
        case .approved: .green
        case .declined: .red
        case .failed: .red
        case .completed: .green
        }
    }
}

/// Single, "effective" status badge for a Seerr request — collapses
/// `request.status` × `request.media?.status` into one readable case.
/// Earlier we rendered both badges side by side, which produced
/// confusing pairs like "Completed · Downloading" and never surfaced
/// the case where a previously-completed item was later deleted from
/// the server (the request stayed at completed but media flipped to
/// unknown / nil — looked like an in-flight download forever).
struct SeerrEffectiveRequestBadge: View {
    let request: SeerrRequest

    var body: some View {
        Label {
            Text(LocalizedStringKey(text))
                .font(.caption)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: icon)
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color, in: Capsule())
    }

    private enum Effective {
        case pending, declined, failed
        case approved, processing
        case partiallyAvailable, available
        case removed
    }

    /// True when Sonarr/Radarr is still tracking the underlying
    /// media. Once the user deletes the file, Seerr clears these
    /// fields. Lets us distinguish a genuinely-downloading request
    /// from one whose file was removed mid-download (Seerr leaves
    /// the request stuck on `.processing` in that case — the user-
    /// visible bug "zeigt 'wird verarbeitet' obwohl längst entfernt
    /// während des downloads").
    private var hasActiveService: Bool {
        request.media?.serviceId != nil
            || request.media?.externalServiceId != nil
    }

    private var effective: Effective {
        switch request.status {
        case .declined: return .declined
        case .failed: return .failed
        case .pendingApproval: return .pending
        case .completed:
            // `completed` is Seerr's "Sonarr/Radarr signed off" flag.
            // If the media is anything other than available /
            // partiallyAvailable now, it was on the server at some
            // point and has since been removed — Seerr keeps the
            // request marked completed but the media status drifts
            // back to processing / unknown / nil.
            switch request.media?.status {
            case .available: return .available
            case .partiallyAvailable: return .partiallyAvailable
            default: return .removed
            }
        case .approved:
            switch request.media?.status {
            case .available: return .available
            case .partiallyAvailable:
                return hasActiveService ? .partiallyAvailable : .removed
            case .processing:
                // Sonarr/Radarr still tracking it → genuine download
                // in flight. Service ids cleared → file was removed
                // before completion.
                return hasActiveService ? .processing : .removed
            case .pending: return .approved
            case .unknown, nil:
                // Approved but Sonarr/Radarr hasn't reported yet —
                // either still spinning up (service ids set) or
                // never picked up / cancelled (service ids nil).
                return hasActiveService ? .processing : .removed
            }
        }
    }

    private var text: String {
        switch effective {
        case .pending: return "catalog.requestStatus.pending"
        case .declined: return "catalog.requestStatus.declined"
        case .failed: return "catalog.requestStatus.failed"
        case .approved: return "catalog.requestStatus.approved"
        case .processing: return "catalog.status.processing"
        case .partiallyAvailable: return "catalog.status.partiallyAvailable"
        case .available: return "catalog.status.available"
        case .removed: return "catalog.status.removed"
        }
    }

    private var icon: String {
        switch effective {
        case .pending: return "clock"
        case .declined: return "xmark"
        case .failed: return "exclamationmark.triangle"
        case .approved: return "checkmark"
        case .processing: return "arrow.triangle.2.circlepath"
        case .partiallyAvailable: return "circle.lefthalf.filled"
        case .available: return "checkmark.circle.fill"
        case .removed: return "trash"
        }
    }

    private var color: Color {
        switch effective {
        case .pending: return .orange
        case .declined: return .red
        case .failed: return .red
        case .approved: return .green
        case .processing: return .blue
        case .partiallyAvailable: return .teal
        case .available: return .green
        case .removed: return .gray
        }
    }
}
