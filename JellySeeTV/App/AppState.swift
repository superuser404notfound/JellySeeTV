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
