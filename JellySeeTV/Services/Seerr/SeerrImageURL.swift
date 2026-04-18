import Foundation

enum SeerrImageURL {
    private static let base = URL(string: "https://image.tmdb.org/t/p")!

    enum PosterSize: String {
        case w342, w500, w780, original
    }

    enum BackdropSize: String {
        case w780, w1280, original
    }

    static func poster(path: String?, size: PosterSize = .w500) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(size.rawValue).appendingPathComponent(cleaned)
    }

    static func backdrop(path: String?, size: BackdropSize = .w1280) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(size.rawValue).appendingPathComponent(cleaned)
    }
}
