import SwiftUI

enum LoadingState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case error(String)
}

struct LoadingStateView<T: Sendable, Content: View>: View {
    let state: LoadingState<T>
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        switch state {
        case .idle:
            Color.clear
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let data):
            content(data)
        case .error(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
