import Foundation

/// Resolves a media item's best-available trailer. Tries local
/// trailers first (bundled Jellyfin media files — full quality, no
/// external apps), falls back to TMDB-sourced YouTube keys pulled
/// from either the Jellyfin RemoteTrailers field or the Jellyseerr
/// relatedVideos array.
@MainActor
final class TrailerService {
    private let libraryService: JellyfinLibraryServiceProtocol
    private let mediaService: SeerrMediaServiceProtocol

    init(
        libraryService: JellyfinLibraryServiceProtocol,
        mediaService: SeerrMediaServiceProtocol
    ) {
        self.libraryService = libraryService
        self.mediaService = mediaService
    }

    /// Resolve a trailer for a Jellyfin-origin item (Home, Library
    /// detail). Preference order: local trailer file > remote YouTube
    /// URL scraped from metadata.
    func resolveTrailer(for item: JellyfinItem) async -> TrailerSource {
        if (item.localTrailerCount ?? 0) > 0 {
            if let first = try? await libraryService.getLocalTrailers(itemID: item.id).first {
                return .local(first)
            }
        }

        if let remoteURLs = item.remoteTrailers?.compactMap({ YouTubeURL.parse(from: $0.url) }),
           let first = remoteURLs.first {
            let name = item.remoteTrailers?.first?.name ?? item.name
            return .youtube(videoKey: first.videoKey, watchURL: first.watchURL, title: name)
        }

        return .unavailable
    }

    /// Resolve a trailer for a Seerr-origin item (Catalog detail —
    /// media the user hasn't downloaded yet, so only remote YouTube
    /// is possible). Picks the first `type=="Trailer"` YouTube entry
    /// from the detail response's relatedVideos, with a fallback to
    /// any YouTube video if no explicit trailer is tagged.
    func resolveTrailer(
        forTMDBID tmdbID: Int,
        mediaType: SeerrMediaType,
        fallbackTitle: String?
    ) async -> TrailerSource {
        let videos: [SeerrVideo]?
        let primaryTitle: String?
        do {
            switch mediaType {
            case .movie:
                let detail = try await mediaService.movieDetail(tmdbID: tmdbID)
                videos = detail.relatedVideos
                primaryTitle = detail.title
            case .tv:
                let detail = try await mediaService.tvDetail(tmdbID: tmdbID)
                videos = detail.relatedVideos
                primaryTitle = detail.name
            case .person:
                return .unavailable
            }
        } catch {
            return .unavailable
        }

        guard let videos else { return .unavailable }

        let title = primaryTitle ?? fallbackTitle

        if let trailer = videos.first(where: { $0.isTrailer && $0.isYouTube }),
           let youtube = YouTubeURL.from(key: trailer.key) {
            return .youtube(
                videoKey: youtube.videoKey,
                watchURL: youtube.watchURL,
                title: trailer.name ?? title
            )
        }
        if let anyYouTube = videos.first(where: { $0.isYouTube }),
           let youtube = YouTubeURL.from(key: anyYouTube.key) {
            return .youtube(
                videoKey: youtube.videoKey,
                watchURL: youtube.watchURL,
                title: anyYouTube.name ?? title
            )
        }
        return .unavailable
    }
}
