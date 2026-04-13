import Foundation

/// A single subtitle entry with timing and text.
struct SubtitleCue: Identifiable {
    let id: Int
    let startTime: Double  // seconds
    let endTime: Double    // seconds
    let text: String
}

/// Parses SRT (SubRip) and WebVTT subtitle files into timed cues.
enum SRTParser {

    /// Parse an SRT/WebVTT string into an array of subtitle cues.
    static func parse(_ content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n")

            // Skip WebVTT header
            if lines.first?.hasPrefix("WEBVTT") == true { continue }

            // Find the timing line (contains "-->")
            guard let timingIdx = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }

            let timingLine = lines[timingIdx]
            guard let (start, end) = parseTimingLine(timingLine) else { continue }

            // Text is everything after the timing line
            let textLines = lines[(timingIdx + 1)...]
            let text = textLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { continue }

            // Strip basic HTML tags (<i>, <b>, <u>, etc.)
            let cleanText = text.replacingOccurrences(
                of: "<[^>]+>",
                with: "",
                options: .regularExpression
            )

            cues.append(SubtitleCue(
                id: cues.count,
                startTime: start,
                endTime: end,
                text: cleanText
            ))
        }

        return cues.sorted { $0.startTime < $1.startTime }
    }

    /// Parse a timing line like "00:01:23,456 --> 00:01:26,789"
    private static func parseTimingLine(_ line: String) -> (Double, Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        guard let start = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }

        return (start, end)
    }

    /// Parse a timestamp like "00:01:23,456" or "00:01:23.456" to seconds.
    private static func parseTimestamp(_ ts: String) -> Double? {
        // Remove any position metadata after the timestamp (WebVTT)
        let clean = ts.components(separatedBy: " ").first ?? ts

        // Normalize comma to dot
        let normalized = clean.replacingOccurrences(of: ",", with: ".")

        let parts = normalized.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }

        if parts.count == 3 {
            // HH:MM:SS.mmm
            guard let h = Double(parts[0]),
                  let m = Double(parts[1]),
                  let s = Double(parts[2]) else { return nil }
            return h * 3600 + m * 60 + s
        } else {
            // MM:SS.mmm
            guard let m = Double(parts[0]),
                  let s = Double(parts[1]) else { return nil }
            return m * 60 + s
        }
    }
}
