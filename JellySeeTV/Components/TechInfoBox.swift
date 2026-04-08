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
        VStack(alignment: .leading, spacing: 20) {
            Text("detail.techInfo")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // Video
                    if let video = videoStream {
                        techCard {
                            Label("detail.tech.video", systemImage: "film")
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .padding(.bottom, 4)

                            if let w = video.width, let h = video.height {
                                techRow("detail.tech.resolution", value: "\(w)×\(h)")
                            }
                            if let codec = video.codec?.uppercased() {
                                let profile = video.profile ?? ""
                                techRow("detail.tech.codec", value: profile.isEmpty ? codec : "\(codec) \(profile)")
                            }
                            if let fps = video.realFrameRate ?? video.averageFrameRate {
                                techRow("detail.tech.framerate", value: String(format: "%.2g fps", fps))
                            }
                            if let range = video.videoRange {
                                techRow("detail.tech.hdr", value: range)
                            }
                        }
                    }

                    // Audio
                    if let audio = audioStreams.first {
                        techCard {
                            Label("detail.tech.audio", systemImage: "speaker.wave.2")
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .padding(.bottom, 4)

                            if let codec = audio.codec?.uppercased() {
                                techRow("detail.tech.codec", value: codec)
                            }
                            if let ch = audio.channels {
                                techRow("detail.tech.channels", value: channelLayout(ch))
                            }
                            if let lang = audio.displayTitle ?? audio.language {
                                techRow("detail.tech.language", value: lang)
                            }
                            if audioStreams.count > 1 {
                                techRow("detail.tech.tracks", value: "\(audioStreams.count)")
                            }
                        }
                    }

                    // File
                    if let source = mediaSource {
                        techCard {
                            Label("detail.tech.file", systemImage: "doc")
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .padding(.bottom, 4)

                            if let container = source.container?.uppercased() {
                                techRow("detail.tech.format", value: container)
                            }
                            if let bitrate = source.bitrate {
                                techRow("detail.tech.bitrate", value: formatBitrate(bitrate))
                            }
                            if let size = source.size {
                                techRow("detail.tech.size", value: formatFileSize(size))
                            }
                            if let path = source.path, let filename = path.split(separator: "/").last {
                                techRow("detail.tech.filename", value: String(filename))
                            }
                        }
                    }

                    // Subtitles
                    if !subtitleStreams.isEmpty {
                        techCard {
                            Label("detail.tech.subtitles", systemImage: "captions.bubble")
                                .font(.caption)
                                .foregroundStyle(.tint)
                                .padding(.bottom, 4)

                            techRow("detail.tech.tracks", value: "\(subtitleStreams.count)")

                            ForEach(subtitleStreams.prefix(4)) { sub in
                                if let lang = sub.displayTitle ?? sub.language {
                                    HStack(spacing: 6) {
                                        Text(lang)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
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
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Card

    private func techCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(20)
        .frame(minWidth: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        )
    }

    private func techRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
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
        if mbps >= 1 {
            return String(format: "%.1f Mbps", mbps)
        }
        return "\(bps / 1000) Kbps"
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}
