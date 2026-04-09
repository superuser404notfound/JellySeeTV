import SwiftUI
import AVKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PlayerViewModel

    init(item: JellyfinItem, startFromBeginning: Bool, playbackService: JellyfinPlaybackServiceProtocol, userID: String) {
        _viewModel = State(initialValue: PlayerViewModel(
            item: item,
            startFromBeginning: startFromBeginning,
            playbackService: playbackService,
            userID: userID
        ))
    }

    var body: some View {
        ZStack {
            if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                VideoPlayer(player: viewModel.coordinator.player)
                    .ignoresSafeArea()
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                        Task {
                            await viewModel.stopPlayback()
                            dismiss()
                        }
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
            Task { await viewModel.stopPlayback() }
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
                dismiss()
            } label: {
                Text("home.retry")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
