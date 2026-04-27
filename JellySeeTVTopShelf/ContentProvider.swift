import os.log
@preconcurrency import TVServices

private let log = Logger(subsystem: "de.superuser404.JellySeeTV.TopShelf", category: "ContentProvider")

/// Apple TV Top Shelf provider. tvOS calls
/// `loadTopShelfContent` when the app icon gets focus on the home
/// screen and (less predictably) on a background refresh schedule.
/// Two failure modes here both surface as an empty shelf: no
/// session yet (signed-out main app) or a transient API error
/// (server offline). Both cases just return nil so the shelf
/// silently falls back to the static brand asset.
///
/// `@objc(JellySeeTVTopShelfContentProvider)` pins an explicit
/// Obj-C class name so PluginKit's `NSClassFromString` lookup
/// against `Info.plist`'s `NSExtensionPrincipalClass` doesn't
/// depend on Swift name-mangling. The target also sets
/// `OTHER_LDFLAGS = -e _NSExtensionMain` so the binary actually
/// boots into the extension lifecycle — the Xcode UI sets that
/// automatically, hand-rolled pbxproj targets do not.
@objc(JellySeeTVTopShelfContentProvider)
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let session = SharedSession.load() else {
            log.notice("No shared session in keychain — TopShelf will render empty.")
            return nil
        }
        let api = JellyfinAPI(session: session)

        async let resume = Self.fetch("resume") { try await api.resumeItems() }
        async let nextUp = Self.fetch("nextUp") { try await api.nextUp() }

        let resumeItems = await resume
        let nextUpItems = await nextUp
        log.info("Fetched resume=\(resumeItems.count) nextUp=\(nextUpItems.count)")

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
