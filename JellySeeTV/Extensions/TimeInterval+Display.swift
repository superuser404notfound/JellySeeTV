import Foundation

extension Int64 {
    /// Convert Jellyfin ticks (100ns units) to a display string like "1h 42m"
    var ticksToDisplay: String {
        let totalSeconds = self / 10_000_000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Convert Jellyfin ticks to TimeInterval (seconds)
    var ticksToSeconds: TimeInterval {
        TimeInterval(self) / 10_000_000
    }
}
