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

        do {
            let detail = try await itemService.getItemDetail(userID: userID, itemID: item.id)
            item = detail
            isFavorite = detail.userData?.isFavorite ?? false
        } catch {
            // Keep existing item data
        }

        // Pre-fetch playback info in background so play starts instantly
        prefetchPlaybackInfo(for: item.id)

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

            // Fallback: find season with in-progress episode
            if targetSeasonID == nil {
                for season in seasons {
                    let eps = try? await itemService.getEpisodes(
                        seriesID: item.id, seasonID: season.id, userID: userID
                    )
                    if let inProgress = eps?.items.first(where: {
                        ($0.userData?.playbackPositionTicks ?? 0) > 0
                    }) {
                        targetSeasonID = season.id
                        targetEpisodeID = inProgress.id
                        break
                    }
                }
            }

            // Load the target season or fallback to first
            let seasonToLoad = targetSeasonID ?? seasons.first?.id
            if let seasonToLoad {
                selectedSeasonID = seasonToLoad
                await loadEpisodes(seasonID: seasonToLoad)
                currentEpisodeID = targetEpisodeID

                // Pre-fetch playback info for the target episode
                if let epID = targetEpisodeID {
                    prefetchPlaybackInfo(for: epID)
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
                profile: DirectPlayProfile.customEngineProfile()
            )
            #if DEBUG
            if cachedPlaybackInfo != nil {
                print("[Prefetch] PlaybackInfo cached for \(itemID)")
            }
            #endif

            // Pre-warm HTTP connection so FFmpeg open is instant
            if let source = cachedPlaybackInfo?.mediaSources.first,
               let url = playbackService.buildStreamURL(
                itemID: itemID, mediaSourceID: source.id,
                container: source.container, isStatic: false
               ) {
                warmUpConnection(to: url)
            }
        }
    }

    /// Send a HEAD request to establish DNS + TCP connection in advance.
    /// The OS connection cache keeps it alive for FFmpeg's subsequent open.
    private func warmUpConnection(to url: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { _, _, _ in
            #if DEBUG
            print("[Prefetch] Connection warmed for \(url.lastPathComponent)")
            #endif
        }.resume()
    }

    func posterURL(for item: JellyfinItem) -> URL? {
        imageService.posterURL(for: item)
    }

    func backdropURL(for item: JellyfinItem) -> URL? {
        imageService.backdropURL(for: item)
    }
}
