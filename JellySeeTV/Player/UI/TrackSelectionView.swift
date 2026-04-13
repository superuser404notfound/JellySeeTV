import SwiftUI
import SteelPlayer

/// Track selection menu — shown when the user taps the track button
/// in the transport bar. Lists available audio and subtitle tracks.
struct TrackSelectionView: View {
    let audioTracks: [TrackInfo]
    let subtitleTracks: [TrackInfo]
    let selectedAudioIndex: Int?
    let selectedSubtitleIndex: Int?
    let onSelectAudio: (Int) -> Void
    let onSelectSubtitle: (Int?) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            // Audio tracks
            if !audioTracks.isEmpty {
                audioTrackList
            }

            // Subtitle tracks
            subtitleTrackList
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 80)
        .padding(.bottom, 180)
    }

    private var audioTrackList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "player.audio", defaultValue: "Audio"), systemImage: "speaker.wave.2")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            ForEach(audioTracks) { track in
                trackButton(
                    name: track.name,
                    detail: track.codec,
                    isSelected: track.id == selectedAudioIndex
                ) {
                    onSelectAudio(track.id)
                }
            }
        }
        .frame(minWidth: 250, alignment: .leading)
    }

    private var subtitleTrackList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "player.subtitles", defaultValue: "Untertitel"), systemImage: "captions.bubble")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            trackButton(
                name: String(localized: "player.subtitles.off", defaultValue: "Aus"),
                detail: nil,
                isSelected: selectedSubtitleIndex == nil
            ) {
                onSelectSubtitle(nil)
            }

            ForEach(subtitleTracks) { track in
                trackButton(
                    name: track.name,
                    detail: track.codec,
                    isSelected: track.id == selectedSubtitleIndex
                ) {
                    onSelectSubtitle(track.id)
                }
            }
        }
        .frame(minWidth: 250, alignment: .leading)
    }

    private func trackButton(
        name: String,
        detail: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            action()
            onDismiss()
        }) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let detail, !isSelected || name != detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
