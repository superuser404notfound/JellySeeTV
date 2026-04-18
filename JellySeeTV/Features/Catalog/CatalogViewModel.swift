import Foundation
import Observation

@MainActor
@Observable
final class CatalogViewModel {
    var trending: [SeerrMedia] = []
    var popularMovies: [SeerrMedia] = []
    var popularTV: [SeerrMedia] = []
    var myRequests: [SeerrRequest] = []

    var isLoadingDiscover = false
    var isLoadingRequests = false
    var errorMessage: String?

    private let discoverService: SeerrDiscoverServiceProtocol
    private let requestService: SeerrRequestServiceProtocol

    init(
        discoverService: SeerrDiscoverServiceProtocol,
        requestService: SeerrRequestServiceProtocol
    ) {
        self.discoverService = discoverService
        self.requestService = requestService
    }

    func loadDiscover() async {
        isLoadingDiscover = true
        errorMessage = nil
        defer { isLoadingDiscover = false }

        do {
            async let trendingTask = discoverService.trending(page: 1)
            async let moviesTask = discoverService.popularMovies(page: 1)
            async let tvTask = discoverService.popularTV(page: 1)

            let (t, m, tv) = try await (trendingTask, moviesTask, tvTask)
            trending = t.results
            popularMovies = m.results
            popularTV = tv.results
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMyRequests() async {
        isLoadingRequests = true
        errorMessage = nil
        defer { isLoadingRequests = false }

        do {
            let result = try await requestService.myRequests(take: 50, skip: 0)
            myRequests = result.results
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
