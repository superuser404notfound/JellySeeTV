import Foundation
import Observation

@Observable
final class AppState {
    var isAuthenticated = false
    var activeServer: JellyfinServer?
    var activeUser: JellyfinUser?
    var isLoading = false

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
