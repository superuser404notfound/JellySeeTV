import os.log
@preconcurrency import TVServices

private let log = Logger(subsystem: "de.superuser404.JellySeeTV.TopShelf", category: "ContentProvider")

/// Apple TV Top Shelf provider. tvOS calls
/// `loadTopShelfContent` when the app icon gets focus on the home
/// screen and (less predictably) on a background refresh schedule.
/// Two failure modes here both surface as an empty shelf: no
/// session yet (signed-out main app) or a transient API error
/// (server offline). Both cases just return nil so the shelf
/// silently falls back to the static brand asset. Errors are
/// logged via `os.Logger` so Console.app on a paired Mac can
/// surface them when the shelf misbehaves.
///
/// `@objc(JellySeeTVTopShelfContentProvider)` pins an explicit
/// Obj-C class name so PluginKit's `NSClassFromString` lookup
/// against `Info.plist`'s `NSExtensionPrincipalClass` doesn't
/// depend on Swift name-mangling. Without this, on tvOS 26 we saw
/// the extension launch and immediately die with PKPlugIn "must
/// have pid! pid: 0" before our principal class could even register
/// with the XPC service — hardening the binding fixes that.
@objc(JellySeeTVTopShelfContentProvider)
final class ContentProvider: TVTopShelfContentProvider {
    /// Forces an early synchronous log line — if this never fires in
    /// Console, the principal class isn't being instantiated at all
    /// and the problem is the Info.plist binding, not our code.
    override init() {
        super.init()
        log.notice("ContentProvider init (build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?", privacy: .public))")
    }

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        log.info("loadTopShelfContent invoked")
        guard let session = SharedSession.load() else {
            log.notice("No shared session in keychain — TopShelf will render empty.")
            return nil
        }
        log.info("Loading TopShelf for user=\(session.userID, privacy: .public) base=\(session.baseURL.absoluteString, privacy: .public)")
        let api = JellyfinAPI(session: session)

        async let resume = Self.fetch("resume") { try await api.resumeItems() }
        async let nextUp = Self.fetch("nextUp") { try await api.nextUp() }

        let resumeItems = await resume
        let nextUpItems = await nextUp
        log.info("Fetched resume=\(resumeItems.count) nextUp=\(nextUpItems.count)")

        // One-shot probe of the first available image URL: the system's
        // image-cache daemon hands us a generic "-17102 decompress
        // failed" with no detail, so we fetch it ourselves and log
        // status + content type to figure out whether Jellyfin is
        // returning JPEG, an HTML 401, or something else entirely.
        if let probe = (resumeItems.first ?? nextUpItems.first)?.topShelfImageURL(
            baseURL: session.baseURL, token: session.accessToken
        ) {
            await Self.probeImage(probe)
        }

        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []

        if !resumeItems.isEmpty {
            let collection = TVTopShelfItemCollection(items: resumeItems.map {
                makeItem(item: $0, session: session)
            })
            collection.title = String(
                localized: "TopShelf.ContinueWatching",
                defaultValue: "Continue Watching"
            )
            sections.append(collection)
        }

        if !nextUpItems.isEmpty {
            let collection = TVTopShelfItemCollection(items: nextUpItems.map {
                makeItem(item: $0, session: session)
            })
            collection.title = String(
                localized: "TopShelf.NextUp",
                defaultValue: "Next Up"
            )
            sections.append(collection)
        }

        guard !sections.isEmpty else { return nil }
        return TVTopShelfSectionedContent(sections: sections)
    }

    private func makeItem(item: JellyfinItem, session: SharedSession) -> TVTopShelfSectionedItem {
        let cell = TVTopShelfSectionedItem(identifier: item.id)
        cell.title = item.topShelfTitle
        cell.imageShape = .hdtv
        cell.displayAction = TVTopShelfAction(url: deepLink(for: item))

        if let url = item.topShelfImageURL(baseURL: session.baseURL, token: session.accessToken) {
            // 2x is the only scale Apple TV actually renders — setting
            // both 1x and 2x doubles the daemon's fetch work and trips
            // memory pressure that can surface as "-17102 decompressing
            // image" when several cells race to decode at once.
            cell.setImageURL(url, for: .screenScale2x)
        } else {
            log.notice("cell \(item.id, privacy: .public) has no image URL")
        }
        return cell
    }

    /// HEAD-style probe: actually fetch the URL ourselves, log the
    /// status code, content type, and a peek at the body. The
    /// system's image daemon swallows all of this and just emits
    /// `-17102` no matter what went wrong, so we have to recreate
    /// the fetch path here.
    private static func probeImage(_ url: URL) async {
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("image/jpeg,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? -1
            let type = http?.value(forHTTPHeaderField: "Content-Type") ?? "?"
            let head = data.prefix(4).map { String(format: "%02X", $0) }.joined()
            log.info("probe url=\(url.absoluteString, privacy: .public) status=\(status, privacy: .public) type=\(type, privacy: .public) bytes=\(data.count, privacy: .public) head=\(head, privacy: .public)")
        } catch {
            log.error("probe url=\(url.absoluteString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `jellyseetv://item/{id}` — handled by the main app's
    /// `onOpenURL` to push directly into the detail/player route
    /// for that item.
    private func deepLink(for item: JellyfinItem) -> URL {
        URL(string: "jellyseetv://item/\(item.id)")!
    }

    private static func fetch(_ label: String, _ work: () async throws -> [JellyfinItem]) async -> [JellyfinItem] {
        do {
            return try await work()
        } catch {
            log.error("\(label, privacy: .public) fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
