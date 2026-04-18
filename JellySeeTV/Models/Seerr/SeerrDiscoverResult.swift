import Foundation

struct SeerrDiscoverResult: Codable, Sendable {
    let page: Int
    let totalPages: Int
    let totalResults: Int
    let results: [SeerrMedia]
}

struct SeerrRequestsResult: Codable, Sendable {
    let pageInfo: SeerrPageInfo
    let results: [SeerrRequest]
}

struct SeerrPageInfo: Codable, Sendable {
    let pages: Int
    let pageSize: Int
    let results: Int
    let page: Int
}
