import Foundation
import Observation

@Observable
final class DetailViewModel {
    var item: JellyfinItem
    var isFavorite: Bool
    var seasons: [JellyfinItem] = []
    var episodes: [JellyfinItem] = []
    var collectionItems: [JellyfinItem] = []
    var currentEpisodeID: String?
    var similarItems: [JellyfinItem] = []
    var selectedSeasonID: String?
    var isLoading = false
    var cachedPlaybackInfo: PlaybackInfoResponse?

    private let itemService: JellyfinItemServiceProtocol
    private let libraryService: JellyfinLibraryServiceProtocol?
    private let playbackService: JellyfinPlaybackServiceProtocol?
    private let imageService: JellyfinImageService
    private let userID: String

    init(
        item: JellyfinItem,
        itemService: JellyfinItemServiceProtocol,
        imageService: JellyfinImageService,
        userID: String,
        libraryService: JellyfinLibraryServiceProtocol? = nil,
        playbackService: JellyfinPlaybackServiceProtocol? = nil
    ) {
        self.item = item
        self.isFavorite = item.userData?.isFavorite ?? false
        self.itemService = itemService
        self.libraryService = libraryService
        self.playbackService = playbackService
        self.imageService = imageService
        self.userID = userID
    }

    func loadFullDetail() async {
        isLoading = true

        let itemID = item.id
        let itemType = item.type

        // Fetch detail + similar. We avoid `async let` here because it
        // interacts badly with @MainActor-isolated service calls crossing
        // back into a non-isolated @Observable class — the task-local
        // allocator ends up deallocating a pointer that is no longer the
        // top of its stack and we crash with
        // swift_task_dealloc_specific SIGABRT "freed pointer was not the
        // last allocation" in asyncLet_finish_after_task_completion.
        // A detached-ish Task{}.value pair stays parallel but keeps each
        // call on its own independent allocator.
        let detailTask = Task { try? await itemService.getItemDetail(userID: userID, itemID: itemID) }
        let similarTask = Task { try? await itemService.getSimilarItems(itemID: itemID, userID: userID, limit: 12) }

        if let detail = await detailTask.value {
            item = detail
            isFavorite = detail.userData?.isFavorite ?? false
        }
        if let similar = await similarTask.value {
            similarItems = similar.items
        }

        // Load content (depends on item type from detail response)
        if itemType == .series {
            await loadSeasons()
        } else if itemType == .boxSet {
            await loadCollectionItems()
        } else {
            prefetchPlaybackInfo(for: itemID)
        }

        isLoading = false
    }

    func loadSeasons() async {
        guard item.type == .series else { return }

        do {
            let response = try await itemService.getSeasons(seriesID: item.id, userID: userID)
            seasons = response.items

            // Try to find the current episode via Next Up
            var targetSeasonID: String?
            var targetEpisodeID: String?

            if let libraryService {
                let nextUp = try? await libraryService.getNextUp(
                    userID: userID, seriesID: item.id, limit: 1
                )
                if let nextEp = nextUp?.items.first {
                    targetSeasonID = nextEp.seasonId
                    targetEpisodeID = nextEp.id
                }
            }

            // Fallback: no NextUp means no watch history → start at season 1

            // Load the target season or fallback to first
            let seasonToLoad = targetSeasonID ?? seasons.first?.id
            if let seasonToLoad {
                selectedSeasonID = seasonToLoad
                await loadEpisodes(seasonID: seasonToLoad)
                currentEpisodeID = targetEpisodeID

                // Pre-fetch playback info for the target episode (or first episode)
                let prefetchID = targetEpisodeID ?? episodes.first?.id
                if let prefetchID {
                    prefetchPlaybackInfo(for: prefetchID)
                }
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

    // MARK: - Playback Info Pre-fetch

    func prefetchPlaybackInfo(for itemID: String) {
        guard let playbackService else { return }
        Task {
            cachedPlaybackInfo = try? await playbackService.getPlaybackInfo(
                itemID: itemID, userID: userID,
                profile: DirectPlayProfile.current()
            )
            #if DEBUG
            if cachedPlaybackInfo != nil {
                print("[Prefetch] PlaybackInfo cached for \(itemID)")
            }
            #endif
        }
    }

    func posterURL(for item: JellyfinItem) -> URL? {
        imageService.posterURL(for: item)
    }

    func backdropURL(for item: JellyfinItem) -> URL? {
        imageService.backdropURL(for: item)
    }
}
