import SwiftUI
import UIKit

/// Authenticated, memory-cached replacement for SwiftUI's
/// `AsyncImage`. Three things the stock version can't do that we
/// need:
///
/// 1. Attach the Jellyfin access token on every request via the
///    `X-Emby-Token` header — SwiftUI's AsyncImage uses
///    URLSession.shared with no way to inject headers, so servers
///    that require auth for image endpoints (the default on modern
///    Jellyfin) silently 401 the request and leave the view on the
///    placeholder. This loader mirrors the same auth mechanism our
///    regular API calls use, so if the API works, images work too.
///
/// 2. Re-issue the load when the URL changes (profile switches
///    swap the token, which changes the URL's `api_key` query). We
///    do that with `.task(id:)` so cancellation is automatic.
///
/// 3. Keep a small in-process image cache. URLSession's shared
///    cache is disk-backed and can serve stale 401 responses
///    across app launches; ours is memory-only and survives only
///    the current session, which is exactly what we want for
///    avatar/poster thumbnails.
struct AsyncCachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.dependencies) private var dependencies
    @State private var loaded: UIImage?

    var body: some View {
        ZStack {
            if let loaded {
                content(Image(uiImage: loaded))
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        // Reset when the URL changes so a stale image from the
        // previous profile's cache doesn't flash while the new one
        // loads.
        loaded = nil
        guard let url else { return }

        if let cached = ImageCache.shared.image(for: url) {
            loaded = cached
            return
        }

        do {
            var request = URLRequest(url: url)
            // Attach the Jellyfin auth header only for requests to
            // the active Jellyfin host — external URLs (TMDB
            // posters in the Seerr catalog, studio logos from
            // third-party CDNs) must not be sent our token.
            if url.host == dependencies.jellyfinClient.baseURL?.host,
               let token = dependencies.jellyfinClient.accessToken,
               !token.isEmpty {
                request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data)
            else { return }
            ImageCache.shared.store(image, for: url)
            guard !Task.isCancelled else { return }
            loaded = image
        } catch {
            // Network / cancellation — placeholder stays visible.
        }
    }
}

extension AsyncCachedImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.content = content
        self.placeholder = { ProgressView() }
    }
}

// MARK: - Cache

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        // Roughly enough for a couple of fully-populated home
        // rows + a detail view's cast list — the OS will evict
        // automatically under memory pressure.
        cache.countLimit = 400
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    /// Wipe the cache on events that should invalidate previous
    /// fetches — primarily profile switches, where a cached poster
    /// loaded with user A's token might be unfetchable with user
    /// B's permissions.
    func clear() {
        cache.removeAllObjects()
    }
}
