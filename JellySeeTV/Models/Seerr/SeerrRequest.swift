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

    init(mediaType: SeerrMediaType, mediaId: Int, seasons: [Int]? = nil) {
        self.mediaType = mediaType
        self.mediaId = mediaId
        self.seasons = seasons
    }
}
