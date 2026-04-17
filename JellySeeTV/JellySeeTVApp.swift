import SwiftUI
import AVFoundation

@main
struct JellySeeTVApp: App {
    @State private var appState = AppState()
    @State private var dependencies = DependencyContainer()

    init() {
        // Pre-warm AVAudioSession at app launch so the first playback
        // doesn't pay the ~500ms setup cost. This runs once and stays
        // active for the app's lifetime.
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, policy: .longFormAudio)
        try? session.setActive(true)
        #endif
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
