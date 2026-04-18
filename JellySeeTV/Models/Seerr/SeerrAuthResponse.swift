import Foundation

/// Body for `POST /api/v1/auth/jellyfin` on an already-configured
/// Seerr server. Seerr rejects any request that re-sends `hostname`
/// once the admin has run the initial setup ("jellyfin hostname
/// already configured", HTTP 500) — so we only send credentials and
/// let the server use the Jellyfin connection it already knows.
///
/// Provisioning a fresh Seerr install from inside the app is out of
/// scope; that's a one-time admin task done through Seerr's web UI.
struct SeerrJellyfinAuthBody: Encodable, Sendable {
    let username: String
    let password: String
}
