import Foundation

/// A Seerr session scoped to a specific Jellyfin profile so profile
/// switching can carry Seerr state across instead of forcing a
/// re-login every time. One entry per (jellyfinServerID,
/// jellyfinUserID) pair.
///
/// The session cookie is a Jellyseerr `connect.sid` value — same
/// kind of token Login writes into SeerrClient.sessionCookie. A 401
/// on restore is the signal to drop the entry and let the user
/// re-authenticate for that specific profile.
struct RememberedSeerrSession: Codable, Sendable, Equatable {
    let jellyfinUserID: String
    let jellyfinServerID: String
    let seerrServer: SeerrServer
    let cookie: String
}
