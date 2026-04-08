import Foundation
import Observation

@Observable
final class DetailViewModel {
    var item: JellyfinItem
    var isFavorite: Bool
    var seasons: [JellyfinItem] = []
    var episodes: [JellyfinItem] = []
    var collectionItems: [JellyfinItem] = []
    var similarItems: [JellyfinItem] = []
    var selectedSeasonID: String?
    var isLoading = false

    private let itemService: JellyfinItemServiceProtocol
    private let imageService: JellyfinImageService
    private let userID: String

    init(
        item: JellyfinItem,
        itemService: JellyfinItemServiceProtocol,
        imageService: JellyfinImageService,
        userID: String
    ) {
        self.item = item
        self.isFavorite = item.userData?.isFavorite ?? false
        self.itemService = itemService
        self.imageService = imageService
        self.userID = userID
    }

    func loadFullDetail() async {
        isLoading = true

        do {
            let detail = try await itemService.getItemDetail(userID: userID, itemID: item.id)
            item = detail
            isFavorite = detail.userData?.isFavorite ?? false
        } catch {
            // Keep existing item data
        }

        // Load similar items
        do {
            let similar = try await itemService.getSimilarItems(itemID: item.id, userID: userID, limit: 12)
            similarItems = similar.items
        } catch {
            // Non-critical
        }

        isLoading = false
    }

    func loadSeasons() async {
        guard item.type == .series else { return }

        do {
            let response = try await itemService.getSeasons(seriesID: item.id, userID: userID)
            seasons = response.items
            if let first = seasons.first {
                selectedSeasonID = first.id
                await loadEpisodes(seasonID: first.id)
            }
        } catch {
            // Handle error
        }
    }

    func loadEpisodes(seasonID: String) async {
        selectedSeasonID = seasonID

        do {
            let response = try await itemService.getEpisodes(seriesID: item.id, seasonID: seasonID, userID: userID)
            episodes = response.items
        } catch {
            // Handle error
        }
    }

    func loadCollectionItems() async {
        guard item.type == .boxSet else { return }

        do {
            let query = ItemQuery(
                parentID: item.id,
                sortBy: "SortName",
                sortOrder: "Ascending",
                limit: 50
            )
            let response = try await itemService.getCollectionItems(userID: userID, query: query)
            collectionItems = response.items
        } catch {
            // Handle error
        }
    }

    func toggleFavorite() async {
        let oldValue = isFavorite
        isFavorite.toggle()

        do {
            try await itemService.setFavorite(userID: userID, itemID: item.id, isFavorite: isFavorite)
            NotificationCenter.default.post(name: .homeFavoritesDidChange, object: nil)
        } catch {
            isFavorite = oldValue
        }
    }

    func posterURL(for item: JellyfinItem) -> URL? {
        imageService.posterURL(for: item)
    }

    func backdropURL(for item: JellyfinItem) -> URL? {
        imageService.backdropURL(for: item)
    }
}
