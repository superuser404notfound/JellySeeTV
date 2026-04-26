import SwiftUI

@main
struct JellySeeTVApp: App {
    @State private var appState = AppState()
    @State private var dependencies = DependencyContainer()

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
