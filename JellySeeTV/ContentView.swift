import SwiftUI

struct ContentView: View {
    var body: some View {
        AppRouter()
    }
}

#Preview {
    ContentView()
        .environment(\.appState, AppState())
        .environment(\.dependencies, DependencyContainer())
}
