@preconcurrency import TVServices

/// Apple TV Top Shelf provider. tvOS calls
/// `loadTopShelfContent` when the app icon gets focus on the home
/// screen and (less predictably) on a background refresh schedule.
/// Two failure modes here both surface as an empty shelf: no
/// session yet (signed-out main app) or a transient API error
/// (server offline). Both cases just return nil so the shelf
/// silently falls back to the static brand asset.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let session = SharedSession.load() else { return nil }
        let api = JellyfinAPI(session: session)

        async let resume = (try? api.resumeItems()) ?? []
        async let nextUp = (try? api.nextUp()) ?? []

        let resumeItems = await resume
        let nextUpItems = await nextUp

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
            cell.setImageURL(url, for: .screenScale1x)
            cell.setImageURL(url, for: .screenScale2x)
        }
        return cell
    }

    /// `jellyseetv://item/{id}` — handled by the main app's
    /// `onOpenURL` to push directly into the detail/player route
    /// for that item.
    private func deepLink(for item: JellyfinItem) -> URL {
        URL(string: "jellyseetv://item/\(item.id)")!
    }
}
