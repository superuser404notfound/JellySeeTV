import SwiftUI

struct TechInfoBox: View {
    let item: JellyfinItem

    private var videoStream: MediaStream? {
        item.mediaStreams?.first { $0.type == .video }
    }

    private var audioStreams: [MediaStream] {
        item.mediaStreams?.filter { $0.type == .audio } ?? []
    }

    private var subtitleStreams: [MediaStream] {
        item.mediaStreams?.filter { $0.type == .subtitle } ?? []
    }

    private var mediaSource: MediaSource? {
        item.mediaSources?.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("detail.techInfo")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if let video = videoStream { videoCard(video) }
                    if let audio = audioStreams.first { audioCard(audio) }
                    if let source = mediaSource { fileCard(source) }
                    if !subtitleStreams.isEmpty { subtitleCard() }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Video

    private func videoCard(_ video: MediaStream) -> some View {
        TechCard(icon: "film", title: "detail.tech.video") {
            if let w = video.width, let h = video.height {
                TechRow(label: "detail.tech.resolution", value: "\(w)×\(h)")
            }
            if let codec = video.codec?.uppercased() {
                let profile = video.profile ?? ""
                TechRow(label: "detail.tech.codec", value: profile.isEmpty ? codec : "\(codec) \(profile)")
            }
            if let fps = video.realFrameRate ?? video.averageFrameRate {
                TechRow(label: "detail.tech.framerate", value: String(format: "%.2g fps", fps))
            }
            if let range = video.videoRange {
                TechRow(label: "detail.tech.hdr", value: range)
            }
        }
    }

    // MARK: - Audio

    private func audioCard(_ audio: MediaStream) -> some View {
        TechCard(icon: "speaker.wave.2", title: "detail.tech.audio") {
            if let codec = audio.codec?.uppercased() {
                TechRow(label: "detail.tech.codec", value: codec)
            }
            if let ch = audio.channels {
                TechRow(label: "detail.tech.channels", value: channelLayout(ch))
            }
            if let lang = audio.displayTitle ?? audio.language {
                TechRow(label: "detail.tech.language", value: lang)
            }
            if audioStreams.count > 1 {
                TechRow(label: "detail.tech.tracks", value: "\(audioStreams.count)")
            }
        }
    }

    // MARK: - File

    private func fileCard(_ source: MediaSource) -> some View {
        TechCard(icon: "doc", title: "detail.tech.file") {
            if let container = source.container?.uppercased() {
                TechRow(label: "detail.tech.format", value: container)
            }
            if let bitrate = source.bitrate {
                TechRow(label: "detail.tech.bitrate", value: formatBitrate(bitrate))
            }
            if let size = source.size {
                TechRow(label: "detail.tech.size", value: formatFileSize(size))
            }
            if let path = source.path, let filename = path.split(separator: "/").last {
                TechRow(label: "detail.tech.filename", value: String(filename))
            }
        }
    }

    // MARK: - Subtitles

    private func subtitleCard() -> some View {
        TechCard(icon: "captions.bubble", title: "detail.tech.subtitles") {
            TechRow(label: "detail.tech.tracks", value: "\(subtitleStreams.count)")

            ForEach(subtitleStreams.prefix(4)) { sub in
                if let lang = sub.displayTitle ?? sub.language {
                    HStack(spacing: 6) {
                        Text(lang)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if sub.isForced == true {
                            Text("F")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(.tertiary))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Formatters

    private func channelLayout(_ channels: Int) -> String {
        switch channels {
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(channels)ch"
        }
    }

    private func formatBitrate(_ bps: Int) -> String {
        let mbps = Double(bps) / 1_000_000
        if mbps >= 1 { return String(format: "%.1f Mbps", mbps) }
        return "\(bps / 1000) Kbps"
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }
}

// MARK: - Tech Card (focusable)

struct TechCard<Content: View>: View {
    let icon: String
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.tint)

            content()
        }
        .padding(24)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isFocused ? .white.opacity(0.1) : .white.opacity(0.05))
        )
        .scaleEffect(isFocused ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .focusable()
        .focused($isFocused)
    }
}

// MARK: - Tech Row

struct TechRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
