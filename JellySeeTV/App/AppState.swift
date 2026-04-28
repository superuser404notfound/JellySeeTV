import Foundation
import Observation

@Observable
final class AppState {
    var isAuthenticated = false
    var activeServer: JellyfinServer?
    var activeUser: JellyfinUser?
    /// Starts as `true` so the brand splash covers the very first
    /// frame — otherwise the underlying view (whichever it is)
    /// flashes for a frame before the AppRouter task can flip it.
    var isLoading = true

    var activeSeerrServer: SeerrServer?
    var activeSeerrUser: SeerrUser?

    /// Set by `onOpenURL` whenever a `jellyseetv://item/{id}` link
    /// arrives — typically from the TopShelf extension. Cleared
    /// after the AppRouter has fetched + presented the item, so a
    /// repeated tap on the same shelf cell still re-fires.
    var pendingDeepLinkItemID: String?

    /// Flipped by `ContinueWatchingIntent` so AppRouter knows to
    /// fetch the latest Resume item and route to it. Kept separate
    /// from `pendingDeepLinkItemID` because the intent runs before
    /// we know which item to play — AppRouter resolves the queue
    /// and then sets `pendingDeepLinkItemID` itself, reusing the
    /// existing TopShelf navigation path.
    var requestContinueWatching: Bool = false

    var isSeerrConnected: Bool {
        activeSeerrServer != nil && activeSeerrUser != nil
    }

    func setAuthenticated(server: JellyfinServer, user: JellyfinUser) {
        activeServer = server
        activeUser = user
        isAuthenticated = true
    }

    func logout() {
        activeServer = nil
        activeUser = nil
        isAuthenticated = false
        activeSeerrServer = nil
        activeSeerrUser = nil
    }

    func setSeerrConnected(server: SeerrServer, user: SeerrUser) {
        activeSeerrServer = server
        activeSeerrUser = user
    }

    func disconnectSeerr() {
        activeSeerrServer = nil
        activeSeerrUser = nil
    }
}
