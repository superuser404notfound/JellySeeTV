import Foundation

struct SeerrUser: Codable, Sendable, Identifiable, Equatable {
    let id: Int
    let email: String?
    let username: String?
    let displayName: String?
    let avatar: String?
    let userType: Int?
    let requestCount: Int?

    var resolvedDisplayName: String {
        displayName ?? username ?? email ?? "User \(id)"
    }
}
