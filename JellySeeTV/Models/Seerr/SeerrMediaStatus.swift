import Foundation

enum SeerrMediaStatus: Int, Codable, Sendable {
    case unknown = 1
    case pending = 2
    case processing = 3
    case partiallyAvailable = 4
    case available = 5

    var localizationKey: String {
        switch self {
        case .unknown: "catalog.status.unknown"
        case .pending: "catalog.status.pending"
        case .processing: "catalog.status.processing"
        case .partiallyAvailable: "catalog.status.partiallyAvailable"
        case .available: "catalog.status.available"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .pending: "clock"
        case .processing: "arrow.triangle.2.circlepath"
        case .partiallyAvailable: "circle.lefthalf.filled"
        case .available: "checkmark.circle.fill"
        }
    }
}

enum SeerrRequestStatus: Int, Codable, Sendable {
    case pendingApproval = 1
    case approved = 2
    case declined = 3

    var localizationKey: String {
        switch self {
        case .pendingApproval: "catalog.requestStatus.pending"
        case .approved: "catalog.requestStatus.approved"
        case .declined: "catalog.requestStatus.declined"
        }
    }
}

enum SeerrMediaType: String, Codable, Sendable {
    case movie
    case tv
    // `/search` also returns `person` results — we decode them so the
    // array parse doesn't fail, then filter them out in the service
    // layer before they reach the UI.
    case person
}
