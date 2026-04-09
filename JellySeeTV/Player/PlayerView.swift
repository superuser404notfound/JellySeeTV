import SwiftUI
import AVKit

struct PlayerView: View {
    @State private var viewModel: PlayerViewModel
    let onDismiss: () -> Void

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String, onDismiss: @escaping () -> Void) {
        _viewModel = State(initialValue: PlayerViewModel(
            item: item,
            startFromBeginning: startFromBeginning,
            playbackService: playbackService,
            userID: userID
        ))
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                VideoPlayer(player: viewModel.coordinator.player)
                    .ignoresSafeArea()
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                        dismissPlayer()
                    }

                if viewModel.isLoading {
                    Color.black
                        .ignoresSafeArea()
                        .overlay(ProgressView())
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: viewModel.isLoading)
        .task {
            await viewModel.startPlayback()
        }
        .onDisappear {
            viewModel.coordinator.player.pause()
            viewModel.coordinator.player.replaceCurrentItem(with: nil)
            Task { await viewModel.stopPlayback() }
        }
    }

    private func dismissPlayer() {
        viewModel.coordinator.player.pause()
        viewModel.coordinator.player.replaceCurrentItem(with: nil)
        Task {
            await viewModel.stopPlayback()
            onDismiss()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
            Button {
                onDismiss()
            } label: {
                Text("home.retry")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
