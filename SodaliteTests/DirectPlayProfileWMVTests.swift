import Testing
import Foundation
@testable import Sodalite

/// The device profile is a promise to the server: every container and codec named in it is one
/// Jellyfin will hand over untouched. Windows Media is the case where that promise is easiest to
/// break by halves, because a `.wmv` needs its container, a video decoder and a decoder for whichever
/// WMA flavour it carries, and a missing audio decoder does not fail the load. It plays the film with
/// no sound, which reads as a bug in the app rather than as a format the app never claimed.
///
/// So the rule this pins is not "asf is listed" but "if asf is listed, the rest is too". The same
/// rule guards the other end of the chain in FFmpegBuild's `DecoderAvailabilityTests`.
@MainActor
struct DirectPlayProfileWMVTests {

    private func videoProfile() -> [String: Any] {
        let profiles = DirectPlayProfile.baseProfile()["DirectPlayProfiles"] as? [[String: Any]] ?? []
        return profiles.first { $0["Type"] as? String == "Video" } ?? [:]
    }

    private func list(_ key: String) -> Set<String> {
        Set((videoProfile()[key] as? String ?? "").components(separatedBy: ","))
    }

    @Test func theProfileOffersTheWindowsMediaContainer() {
        #expect(list("Container").isSuperset(of: ["asf", "wmv"]))
    }

    /// Jellyfin names the flavours the way ffprobe does, so these are the strings that decide whether
    /// a WMA track is handed over or transcoded.
    @Test func offeringThatContainerMeansOfferingEveryWMAFlavour() {
        guard !list("Container").isDisjoint(with: ["asf", "wmv"]) else { return }
        #expect(list("AudioCodec").isSuperset(
            of: ["wmav1", "wmav2", "wmapro", "wmalossless", "wmavoice"]))
    }

    @Test func offeringThatContainerMeansOfferingItsVideoCodecs() {
        guard !list("Container").isDisjoint(with: ["asf", "wmv"]) else { return }
        #expect(list("VideoCodec").isSuperset(of: ["wmv1", "wmv2", "wmv3", "vc1"]))
    }
}
