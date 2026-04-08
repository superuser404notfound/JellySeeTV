import Foundation
import Observation

@Observable
final class DetailViewModel {
    var item: JellyfinItem
    var seasons: [JellyfinItem] = []
    var episodes: [JellyfinItem] = []
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
        self.itemService = itemService
        self.imageService = imageService
        self.userID = userID
    }

    func loadFullDetail() async {
        isLoading = true

        do {
            let detail = try await itemService.getItemDetail(userID: userID, itemID: item.id)
            item = detail
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

    func toggleFavorite() async {
        let currentlyFavorite = item.userData?.isFavorite ?? false
        let newValue = !currentlyFavorite

        // Optimistic update
        var updatedUserData = item.userData ?? UserItemData(
            playbackPositionTicks: nil, playCount: nil,
            isFavorite: nil, played: nil,
            unplayedItemCount: nil, playedPercentage: nil
        )
        updatedUserData = UserItemData(
            playbackPositionTicks: updatedUserData.playbackPositionTicks,
            playCount: updatedUserData.playCount,
            isFavorite: newValue,
            played: updatedUserData.played,
            unplayedItemCount: updatedUserData.unplayedItemCount,
            playedPercentage: updatedUserData.playedPercentage
        )
        item = JellyfinItem(item: item, userData: updatedUserData)

        do {
            try await itemService.setFavorite(userID: userID, itemID: item.id, isFavorite: newValue)
        } catch {
            // Revert on failure
            item = JellyfinItem(item: item, userData: UserItemData(
                playbackPositionTicks: updatedUserData.playbackPositionTicks,
                playCount: updatedUserData.playCount,
                isFavorite: currentlyFavorite,
                played: updatedUserData.played,
                unplayedItemCount: updatedUserData.unplayedItemCount,
                playedPercentage: updatedUserData.playedPercentage
            ))
        }
    }

    func posterURL(for item: JellyfinItem) -> URL? {
        imageService.posterURL(for: item)
    }

    func backdropURL(for item: JellyfinItem) -> URL? {
        imageService.backdropURL(for: item)
    }
}
