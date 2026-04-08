import Foundation

enum GenreFilter {
    static let primary: Set<String> = [
        "Action",
        "Adventure",
        "Animation",
        "Comedy",
        "Crime",
        "Documentary",
        "Drama",
        "Family",
        "Fantasy",
        "History",
        "Horror",
        "Music",
        "Mystery",
        "Romance",
        "Science Fiction",
        "Thriller",
        "War",
        "Western",
    ]

    static func isPrimary(_ genreName: String) -> Bool {
        let lowered = genreName.lowercased()
        return primary.contains { $0.lowercased() == lowered }
    }
}
