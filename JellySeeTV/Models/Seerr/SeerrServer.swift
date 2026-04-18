import Foundation

struct SeerrServer: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let url: URL

    init(id: String = UUID().uuidString, url: URL) {
        self.id = id
        self.url = url
    }
}
