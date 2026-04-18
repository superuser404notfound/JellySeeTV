import Foundation

struct SeerrJellyfinAuthBody: Encodable, Sendable {
    let username: String
    let password: String
    let hostname: String
    let port: Int?
    let urlBase: String?
    let useSsl: Bool
    let email: String?
    let serverType: Int

    init(
        username: String,
        password: String,
        jellyfinURL: URL,
        email: String? = nil
    ) {
        self.username = username
        self.password = password
        self.hostname = jellyfinURL.host ?? ""
        self.port = jellyfinURL.port
        self.urlBase = jellyfinURL.path.isEmpty ? nil : jellyfinURL.path
        self.useSsl = jellyfinURL.scheme == "https"
        self.email = email
        self.serverType = 2
    }
}
