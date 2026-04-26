import SwiftUI

@main
struct JellySeeTVApp: App {
    @State private var appState = AppState()
    @State private var dependencies = DependencyContainer()

    init() {
        // FIRST thing the app does — before any other UserDefaults
        // reader/writer touches CFPreferences. Earlier builds wrote
        // the home + catalog filter caches into UserDefaults, which
        // tvOS caps at 1 MB per app domain. Once that ceiling is hit
        // any subsequent `defaults.set(...)` (even unrelated tiny
        // writes from other features) crashes the app with SIGABRT
        // because CFPreferences re-flushes the *entire* plist on
        // every change. Sweep those legacy keys out before anything
        // else loads so the plist drops back under the limit.
        Self.purgeLegacyFilterCacheDefaults()
    }

    private static func purgeLegacyFilterCacheDefaults() {
        let defaults = UserDefaults.standard
        let prefixes = [
            "FilterCache.homeItems.",
            "FilterCache.smart.",
            "FilterCache.catalog.",
        ]
        for key in defaults.dictionaryRepresentation().keys
        where prefixes.contains(where: key.hasPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(\.appState, appState)
                .environment(\.dependencies, dependencies)
                .preferredColorScheme(.dark)
                .tint(dependencies.appearancePreferences.effectiveTint(
                    isSupporter: dependencies.storeKitService.isSupporter
                ))
        }
    }
}
