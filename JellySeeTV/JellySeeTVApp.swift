import SwiftUI
import AVFoundation

@main
struct JellySeeTVApp: App {
    @State private var appState = AppState()
    @State private var dependencies = DependencyContainer()

    init() {
        // Pre-warm AVFoundation framework to eliminate first-play delay
        let warmup = AVPlayer()
        warmup.replaceCurrentItem(with: nil)
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
