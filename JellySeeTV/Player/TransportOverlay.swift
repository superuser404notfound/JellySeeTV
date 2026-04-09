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
    @FocusState private var focusedButton: TransportButton?

    enum TransportButton: Hashable {
        case seekBack, playPause, seekForward, audio, subtitle
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 20) {
                // Title
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2)).frame(height: 6)
                        Capsule().fill(.tint).frame(width: max(0, geo.size.width * CGFloat(progress)), height: 6)
                    }
                }
                .frame(height: 6)

                // Time
                HStack {
                    Text(currentTime)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(totalTime)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                // Transport buttons
                HStack(spacing: 40) {
                    transportButton(icon: "gobackward.10", focused: .seekBack) {
                        onSeekBackward()
                    }

                    transportButton(icon: isPlaying ? "pause.fill" : "play.fill", focused: .playPause, isLarge: true) {
                        onTogglePlayPause()
                    }

                    transportButton(icon: "goforward.10", focused: .seekForward) {
                        onSeekForward()
                    }
                }

                // Track selection
                HStack(spacing: 24) {
                    if audioTracks.count > 1 {
                        transportButton(
                            label: currentAudioName,
                            icon: "speaker.wave.2",
                            focused: .audio
                        ) {
                            showAudioPicker.toggle()
                            showSubtitlePicker = false
                        }
                    }

                    if !subtitleTracks.isEmpty {
                        transportButton(
                            label: currentSubtitleName,
                            icon: "captions.bubble",
                            focused: .subtitle
                        ) {
                            showSubtitlePicker.toggle()
                            showAudioPicker = false
                        }
                    }
                }

                // Pickers
                if showAudioPicker {
                    trackPicker(
                        tracks: audioTracks,
                        currentIndex: currentAudioIndex,
                        onSelect: { onSelectAudio($0); showAudioPicker = false }
                    )
                }

                if showSubtitlePicker {
                    trackPicker(
                        tracks: [(-1, "Off")] + subtitleTracks,
                        currentIndex: currentSubtitleIndex,
                        onSelect: { onSelectSubtitle($0); showSubtitlePicker = false }
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
        .onAppear {
            focusedButton = .playPause
        }
    }

    // MARK: - Transport Button

    private func transportButton(label: String? = nil, icon: String, focused: TransportButton, isLarge: Bool = false, action: @escaping () -> Void) -> some View {
        Button { action() } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(isLarge ? .title : .title3)
                if let label {
                    Text(label)
                        .font(.caption)
                }
            }
            .padding(.horizontal, label != nil ? 16 : 8)
            .padding(.vertical, 8)
        }
        .buttonStyle(TransportButtonStyle())
        .focused($focusedButton, equals: focused)
    }

    // MARK: - Track Picker

    private func trackPicker(tracks: [(index: Int, name: String)], currentIndex: Int, onSelect: @escaping (Int) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tracks, id: \.index) { track in
                    Button {
                        onSelect(track.index)
                    } label: {
                        HStack(spacing: 6) {
                            Text(track.name)
                                .font(.caption)
                            if track.index == currentIndex {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(TransportButtonStyle())
                }
            }
        }
    }

    // MARK: - Helpers

    private var currentAudioName: String {
        audioTracks.first { $0.index == currentAudioIndex }?.name ?? "Audio"
    }

    private var currentSubtitleName: String {
        if currentSubtitleIndex < 0 { return "Off" }
        return subtitleTracks.first { $0.index == currentSubtitleIndex }?.name ?? "Subtitles"
    }
}

// MARK: - Button Style

struct TransportButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? .white.opacity(0.2) : .clear)
            )
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
