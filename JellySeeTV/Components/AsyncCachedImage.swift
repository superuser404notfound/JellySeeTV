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

        // Build the request on MainActor — we need to read the
        // Jellyfin client's token, which is MainActor-isolated.
        // Attach the auth header only for requests to the active
        // Jellyfin host; external URLs (TMDB posters in the Seerr
        // catalog, studio logos from third-party CDNs) must not
        // see our token.
        var request = URLRequest(url: url)
        if url.host == dependencies.jellyfinClient.baseURL?.host,
           let token = dependencies.jellyfinClient.accessToken,
           !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }

        let prepared = await Self.fetchAndDecode(request: request)
        guard let prepared else { return }
        // Persist to cache *before* the cancellation check. A tab
        // switch (or any upstream `.task(id:)` invalidation) may
        // cancel us between the successful decode and the @State
        // write — but the bytes are already in memory. Skipping the
        // cache here meant the next mount paid the bandwidth + decode
        // again for the same URL, which on a flaky connection or a
        // 30-season show with 20 stills per tab adds up fast.
        ImageCache.shared.store(prepared, for: url)
        guard !Task.isCancelled else { return }
        loaded = prepared
    }

    /// Network + decode + force-decompress, all off the MainActor.
    /// `preparingForDisplay()` performs the pixel decode now, so the
    /// first draw on MainActor doesn't pay that cost as a frame-drop
    /// during a scroll. Static + `nonisolated` lets the call hop to
    /// the cooperative thread pool instead of being pinned to
    /// MainActor by structural inference. Cancellation propagates via
    /// structured concurrency: when the enclosing `.task(id: url)` is
    /// cancelled (URL change, view disappearance), URLSession.data
    /// inherits the cancellation and aborts.
    nonisolated private static func fetchAndDecode(request: URLRequest) async -> UIImage? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data)
            else { return nil }
            return image.preparingForDisplay() ?? image
        } catch {
            return nil
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
        // Cost-based eviction. Each store carries its decoded byte
        // size as cost, so NSCache auto-evicts when the total exceeds
        // the limit — enough for a couple of fully-populated home
        // rows plus a detail backdrop on a 4K display, but bounded so
        // a long browsing session doesn't keep growing into hundreds
        // of MB. countLimit stays generous so it's not the gating
        // factor; the byte budget is what we care about.
        cache.totalCostLimit = 150_000_000
        cache.countLimit = 1000
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL, cost: estimatedBytes(for: image))
    }

    /// Wipe the cache on events that should invalidate previous
    /// fetches — primarily profile switches, where a cached poster
    /// loaded with user A's token might be unfetchable with user
    /// B's permissions.
    func clear() {
        cache.removeAllObjects()
    }

    /// Decoded size estimate: width × height × scale² × 4 bytes (RGBA8).
    /// Doesn't account for HDR/wide-gamut backing stores, but good
    /// enough as a cost signal for NSCache's eviction policy.
    private func estimatedBytes(for image: UIImage) -> Int {
        let scale = image.scale
        let pixels = image.size.width * scale * image.size.height * scale
        return Int(pixels) * 4
    }
}
