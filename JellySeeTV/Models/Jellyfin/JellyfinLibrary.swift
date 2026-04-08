import Foundation

struct JellyfinLibrary: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let collectionType: String?
    let imageTags: ImageTags?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case collectionType = "CollectionType"
        case imageTags = "ImageTags"
    }

    var libraryType: LibraryType {
        guard let collectionType else { return .unknown }
        return LibraryType(rawValue: collectionType) ?? .unknown
    }
}

enum LibraryType: String, Sendable {
    case movies
    case tvshows
    case music
    case books
    case homevideos
    case boxsets
    case unknown
}

struct JellyfinItemsResponse: Codable, Sendable {
    let items: [JellyfinItem]
    let totalRecordCount: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}
