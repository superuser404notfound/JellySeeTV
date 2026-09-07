import Testing
import Foundation
@testable import Sodalite

/// The Top Shelf's burned-in artwork is addressed by file URL, and the home screen caches by URL.
/// The name is therefore the whole cache key: anything that changes the drawn pixels has to move
/// it, and anything that does not has to leave it alone.
@MainActor
struct ResumeBarFileTests {

    private let remote = URL(string: "https://jf.example.com/Items/abc/Images/Primary?tag=t1&maxWidth=1280&api_key=k1")!

    private func name(itemID: String = "abc",
                      remote: URL? = nil,
                      fraction: Double = 0.5,
                      accent: UInt32 = 0xFF3B30) -> String {
        ResumeBarFile.name(itemID: itemID,
                           remote: remote ?? self.remote,
                           fraction: fraction,
                           accent: accent)
    }

    @Test("progress moves the name")
    func progressIsPartOfTheKey() {
        #expect(name(fraction: 0.5) != name(fraction: 0.62))
    }

    @Test("the accent moves the name")
    func accentIsPartOfTheKey() {
        #expect(name(accent: 0xFF3B30) != name(accent: 0x0A84FF))
    }

    @Test("the render version moves the name")
    func renderVersionIsPartOfTheKey() {
        #expect(name().hasPrefix("bar\(ResumeBarFile.renderVersion)-"))
    }

    @Test("new artwork on the same item moves the name")
    func imageTagIsPartOfTheKey() {
        let reimaged = URL(string: "https://jf.example.com/Items/abc/Images/Primary?tag=t2&maxWidth=1280&api_key=k1")!
        #expect(name() != name(remote: reimaged))
    }

    @Test("two items never share a file")
    func itemIsPartOfTheKey() {
        #expect(name(itemID: "abc") != name(itemID: "def"))
    }

    /// The token rotates on its own schedule. Keying on it would throw the whole directory away
    /// every rotation and put the shelf back on a cold pass for no visual reason.
    @Test("a rotated access token does not move the name")
    func tokenIsNotPartOfTheKey() {
        let rotated = URL(string: "https://jf.example.com/Items/abc/Images/Primary?tag=t1&maxWidth=1280&api_key=k2")!
        #expect(name() == name(remote: rotated))
    }

    /// Ids and tags come from a server, so they land in a path component only after sanitizing.
    @Test("the name is a single safe path component")
    func nameIsPathSafe() {
        let hostile = URL(string: "https://jf.example.com/Items/x/Images/Primary?tag=../../etc&api_key=k")!
        let value = name(itemID: "a/b c", remote: hostile)
        #expect(!value.contains("/"))
        #expect(!value.contains(".."))
        #expect(value.hasSuffix(".jpg"))
    }

    /// The percent is what the reader sees, so it is what the file has to be keyed on; a fraction
    /// that rounds to the same percent is the same picture.
    @Test("progress is keyed at whole percent")
    func progressRoundsToPercent() {
        #expect(name(fraction: 0.5001) == name(fraction: 0.4999))
    }

    @Test("progress outside 0...1 still names a file")
    func progressIsClamped() {
        #expect(name(fraction: 1.4) == name(fraction: 1.0))
        #expect(name(fraction: -0.2) == name(fraction: 0.0))
    }
}
