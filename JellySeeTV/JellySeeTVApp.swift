import SwiftUI
import AVFoundation

@main
struct JellySeeTVApp: App {
    @State private var appState = AppState()
    @State private var dependencies = DependencyContainer()

    init() {
        // Pre-warm AVFoundation so first playback doesn't have a loading delay
        _ = AVPlayer()
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(\.appState, appState)
                .environment(\.dependencies, dependencies)
                .preferredColorScheme(.dark)
        }
    }
}
