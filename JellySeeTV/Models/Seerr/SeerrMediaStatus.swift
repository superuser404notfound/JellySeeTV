import Foundation

enum SeerrMediaStatus: Int, Codable, Sendable {
    case unknown = 1
    case pending = 2
    case processing = 3
    case partiallyAvailable = 4
    case available = 5

    // Lenient decoding: future Seerr versions have already added more
    // states (e.g. a "deleted" value has shown up on some servers).
    // An unknown int would otherwise abort the whole /movie/{id} or
    // /tv/{id} decode, breaking the catalog-detail view for any item
    // with an exotic status. Fall back to `.unknown` and let the UI
    // handle it gracefully.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        self = SeerrMediaStatus(rawValue: raw) ?? .unknown
    }

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
    case failed = 4
    case completed = 5

    // Same lenient pattern as SeerrMediaStatus. The `completed = 5`
    // value is what tripped us up — Seerr returns it for every request
    // attached to an already-available movie/series, so any library
    // item the user owns would fail to decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        self = SeerrRequestStatus(rawValue: raw) ?? .pendingApproval
    }

    var localizationKey: String {
        switch self {
        case .pendingApproval: "catalog.requestStatus.pending"
        case .approved: "catalog.requestStatus.approved"
        case .declined: "catalog.requestStatus.declined"
        case .failed: "catalog.requestStatus.failed"
        case .completed: "catalog.requestStatus.completed"
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
