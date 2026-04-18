import Foundation

struct SeerrJellyfinAuthBody: Encodable, Sendable {
    let username: String
    let password: String
    let hostname: String
    let port: Int
    let urlBase: String
    let useSsl: Bool

    init(
        username: String,
        password: String,
        jellyfinURL: URL
    ) {
        self.username = username
        self.password = password
        self.hostname = jellyfinURL.host ?? ""
        self.useSsl = jellyfinURL.scheme == "https"
        // Port is required by the API; default to Jellyfin's standard
        // ports when the URL omits it (reverse-proxy on 443/80 still
        // needs an explicit number, not null — null triggers HTTP 500
        // on Jellyseerr's /auth/jellyfin endpoint).
        self.port = jellyfinURL.port ?? (useSsl ? 443 : 80)
        // urlBase must be a string ("") rather than null or absent —
        // Jellyseerr concatenates it into the connection URL and rejects
        // null with a 500.
        let path = jellyfinURL.path
        self.urlBase = (path.isEmpty || path == "/") ? "" : path
    }
}
