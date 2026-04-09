import Foundation

/// Temporary stub -- will be rebuilt for custom engine (universal DirectPlay)
enum DirectPlayProfile {
    static func avPlayerProfile() -> [String: Any] { [:] }
    static func vlcKitProfile() -> [String: Any] { [:] }
    static var displaySupportsHDR: Bool { false }
}
