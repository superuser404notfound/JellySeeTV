import Foundation
import Observation

@Observable
final class HomeViewModel {
    var continueWatching: [JellyfinItem] = []
    var nextUp: [JellyfinItem] = []
    var latestMovies: [JellyfinItem] = []
    var latestShows: [JellyfinItem] = []
    var libraries: [JellyfinLibrary] = []
    var isLoading = true
    var errorMessage: String?

    private let libraryService: JellyfinLibraryServiceProtocol
    private let imageService: JellyfinImageService
    private let userID: String

    init(
        libraryService: JellyfinLibraryServiceProtocol,
        imageService: JellyfinImageService,
        userID: String
    ) {
        self.libraryService = libraryService
        self.imageService = imageService
        self.userID = userID
    }

    func loadContent() async {
        isLoading = true
        errorMessage = nil

        do {
            async let libs = libraryService.getLibraries(userID: userID)
            async let resume = libraryService.getResumeItems(userID: userID, mediaType: "Video", limit: 12)
            async let next = libraryService.getNextUp(userID: userID, seriesID: nil, limit: 12)
            async let latestM = libraryService.getLatestMedia(userID: userID, parentID: nil, limit: 16)

            let (libsResult, resumeResult, nextResult, latestResult) = try await (libs, resume, next, latestM)

            libraries = libsResult
            continueWatching = resumeResult.items
            nextUp = nextResult.items

            // Split latest into movies and shows
            latestMovies = latestResult.filter { $0.type == .movie }
            latestShows = latestResult.filter { $0.type == .episode || $0.type == .series }

            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func posterURL(for item: JellyfinItem) -> URL? {
        imageService.posterURL(for: item)
    }
}
