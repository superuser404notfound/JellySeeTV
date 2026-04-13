import SwiftUI
import SteelPlayer

/// Track selection menu — audio and subtitle track picker.
/// Shown as an overlay at the bottom of the player.
struct TrackSelectionView: View {
    let audioTracks: [TrackInfo]
    let subtitleTracks: [TrackInfo]
    let selectedAudioIndex: Int?
    let selectedSubtitleIndex: Int?
    let onSelectAudio: (Int) -> Void
    let onSelectSubtitle: (Int?) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 40) {
                if !audioTracks.isEmpty {
                    audioTrackList
                }
                subtitleTrackList
            }
            .padding(40)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 80)
        .padding(.bottom, 120)
        .onExitCommand { onDismiss() }
    }

    // MARK: - Audio Tracks

    private var audioTrackList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Audio", systemImage: "speaker.wave.2")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
                .focusable(false)

            ForEach(audioTracks) { track in
                trackRow(
                    name: track.name,
                    detail: track.codec,
                    isSelected: track.id == selectedAudioIndex
                ) {
                    onSelectAudio(track.id)
                    onDismiss()
                }
            }
        }
        .frame(minWidth: 280, alignment: .leading)
    }

    // MARK: - Subtitle Tracks

    private var subtitleTrackList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                String(localized: "player.subtitles", defaultValue: "Untertitel"),
                systemImage: "captions.bubble"
            )
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
            .focusable(false)

            trackRow(
                name: String(localized: "player.subtitles.off", defaultValue: "Aus"),
                detail: nil,
                isSelected: selectedSubtitleIndex == nil
            ) {
                onSelectSubtitle(nil)
                onDismiss()
            }

            ForEach(subtitleTracks) { track in
                trackRow(
                    name: track.name,
                    detail: track.codec,
                    isSelected: track.id == selectedSubtitleIndex
                ) {
                    onSelectSubtitle(track.id)
                    onDismiss()
                }
            }
        }
        .frame(minWidth: 280, alignment: .leading)
    }

    // MARK: - Track Row

    private func trackRow(
        name: String,
        detail: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.card)
    }
}
