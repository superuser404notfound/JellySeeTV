import Foundation

/// Hand-off point between AppIntent's `perform()` (which can run
/// in a fresh app launch triggered by Siri/Shortcuts) and the
/// running SwiftUI scene.
///
/// `openAppWhenRun = true` on each intent guarantees the host app
/// has finished its launch sequence by the time `perform()` is
/// called, so reading `appState`/`dependencies` here is always
/// safe-after-launch. The intent then mutates `pendingDeepLinkItemID`
/// or `appState.activeUser`, and `AppRouter`'s observers pick up
/// the change and drive the navigation.
@MainActor
enum IntentBridge {
    static weak var appState: AppState?
    static weak var dependencies: DependencyContainer?

    static func bind(appState: AppState, dependencies: DependencyContainer) {
        Self.appState = appState
        Self.dependencies = dependencies
    }
}
