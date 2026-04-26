import Foundation

struct SeerrRequest: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let status: SeerrRequestStatus
    let createdAt: String?
    let updatedAt: String?
    let type: SeerrMediaType
    let is4k: Bool?
    let media: SeerrRequestMedia?
    let seasons: [SeerrRequestSeason]?
    let requestedBy: SeerrUser?
}

struct SeerrRequestMedia: Codable, Sendable, Equatable {
    let id: Int?
    let tmdbId: Int?
    let mediaType: SeerrMediaType?
    let status: SeerrMediaStatus?
    /// Sonarr/Radarr server id the media is attached to.
    let serviceId: Int?
    let externalServiceId: Int?
    /// Live Sonarr/Radarr queue snapshot Seerr fills at request
    /// time. An empty array (or `nil` from older Seerr versions)
    /// means no queue entry — paired with `status = .processing`
    /// that's the most reliable "Sonarr was told to download this,
    /// then it disappeared from the queue (cancelled, removed,
    /// killed)" signal we have. Service ids stick around in
    /// Seerr's DB even after the queue clears, so they aren't
    /// enough on their own.
    let downloadStatus: [SeerrDownloadingItem]?
    let downloadStatus4k: [SeerrDownloadingItem]?
}

/// Minimal stand-in for a Sonarr/Radarr queue entry. We only need
/// to know whether the array has anything in it — the granular
/// fields aren't read anywhere. Optional fields decode to `nil`
/// when missing so we stay forwards-compatible with whatever
/// shape Seerr's downloadStatus payload takes.
struct SeerrDownloadingItem: Codable, Sendable, Equatable {
    let externalId: Int?
    let title: String?
}

struct SeerrRequestSeason: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let seasonNumber: Int
    let status: SeerrMediaStatus?
}

struct SeerrCreateRequestBody: Encodable, Sendable {
    let mediaType: SeerrMediaType
    let mediaId: Int
    let seasons: [Int]?
    let serverId: Int?
    let profileId: Int?
    let rootFolder: String?
    let languageProfileId: Int?

    init(
        mediaType: SeerrMediaType,
        mediaId: Int,
        seasons: [Int]? = nil,
        serverId: Int? = nil,
        profileId: Int? = nil,
        rootFolder: String? = nil,
        languageProfileId: Int? = nil
    ) {
        self.mediaType = mediaType
        self.mediaId = mediaId
        self.seasons = seasons
        self.serverId = serverId
        self.profileId = profileId
        self.rootFolder = rootFolder
        self.languageProfileId = languageProfileId
    }
}
