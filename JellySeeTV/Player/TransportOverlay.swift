import SwiftUI

struct TransportOverlay: View {
    let title: String
    let isPlaying: Bool
    let currentTime: String
    let totalTime: String
    let progress: Float
    let audioTracks: [(index: Int, name: String)]
    let subtitleTracks: [(index: Int, name: String)]
    let currentAudioIndex: Int
    let currentSubtitleIndex: Int
    let onTogglePlayPause: () -> Void
    let onSeekForward: () -> Void
    let onSeekBackward: () -> Void
    let onSelectAudio: (Int) -> Void
    let onSelectSubtitle: (Int) -> Void

    @State private var showAudioPicker = false
    @State private var showSubtitlePicker = false

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                // Title
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track
                        Capsule()
                            .fill(.white.opacity(0.2))
                            .frame(height: 6)

                        // Progress
                        Capsule()
                            .fill(.tint)
                            .frame(width: max(0, geo.size.width * CGFloat(progress)), height: 6)
                    }
                }
                .frame(height: 6)

                // Time + controls
                HStack {
                    Text(currentTime)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Spacer()

                    // Seek back
                    HStack(spacing: 30) {
                        Button { onSeekBackward() } label: {
                            Image(systemName: "gobackward.10")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        // Play/Pause
                        Button { onTogglePlayPause() } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)

                        // Seek forward
                        Button { onSeekForward() } label: {
                            Image(systemName: "goforward.10")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text(totalTime)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                // Track selection
                HStack(spacing: 20) {
                    if audioTracks.count > 1 {
                        Button {
                            showAudioPicker.toggle()
                            showSubtitlePicker = false
                        } label: {
                            Label(currentAudioName, systemImage: "speaker.wave.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if !subtitleTracks.isEmpty {
                        Button {
                            showSubtitlePicker.toggle()
                            showAudioPicker = false
                        } label: {
                            Label(currentSubtitleName, systemImage: "captions.bubble")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Track picker popups
                if showAudioPicker {
                    trackPicker(
                        title: "Audio",
                        tracks: audioTracks,
                        currentIndex: currentAudioIndex,
                        onSelect: { index in
                            onSelectAudio(index)
                            showAudioPicker = false
                        }
                    )
                }

                if showSubtitlePicker {
                    trackPicker(
                        title: "Subtitles",
                        tracks: [(-1, "Off")] + subtitleTracks,
                        currentIndex: currentSubtitleIndex,
                        onSelect: { index in
                            onSelectSubtitle(index)
                            showSubtitlePicker = false
                        }
                    )
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
        }
    }

    private var currentAudioName: String {
        audioTracks.first { $0.index == currentAudioIndex }?.name ?? "Audio"
    }

    private var currentSubtitleName: String {
        if currentSubtitleIndex < 0 { return "Off" }
        return subtitleTracks.first { $0.index == currentSubtitleIndex }?.name ?? "Subtitles"
    }

    private func trackPicker(title: String, tracks: [(index: Int, name: String)], currentIndex: Int, onSelect: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tracks, id: \.index) { track in
                Button {
                    onSelect(track.index)
                } label: {
                    HStack {
                        Text(track.name)
                            .font(.caption)
                        Spacer()
                        if track.index == currentIndex {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .padding(.top, 8)
    }
}
