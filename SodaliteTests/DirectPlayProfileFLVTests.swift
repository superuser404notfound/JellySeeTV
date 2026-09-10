import Testing
import Foundation
@testable import Sodalite

/// Flash Video, the second chain that can be offered by halves.
///
/// `flv` has been in the container list from the start, which was correct for a file from after
/// 2008: H.264 and AAC were always in the build, so those direct-played. The legacy tail was not,
/// so a Sorenson Spark or VP6 file went to the server and came back transcoded. FFmpegBuild 3.2.0
/// puts the decoders in, and the profile follows in the same pass, because the two halves of the
/// promise fail differently: an unlisted VIDEO codec costs a transcode, while listing a container
/// whose AUDIO codecs the engine's FFmpeg build cannot decode hands over a film it then plays
/// without sound, since the audio bridge has no decoder to open and the session goes video-only.
@MainActor
struct DirectPlayProfileFLVTests {

    private func videoProfile() -> [String: Any] {
        let profiles = DirectPlayProfile.baseProfile()["DirectPlayProfiles"] as? [[String: Any]] ?? []
        return profiles.first { $0["Type"] as? String == "Video" } ?? [:]
    }

    private func list(_ key: String) -> Set<String> {
        Set((videoProfile()[key] as? String ?? "").components(separatedBy: ","))
    }

    @Test func theProfileOffersTheFlashContainer() {
        #expect(list("Container").contains("flv"))
    }

    /// `flv1` is the name ffprobe reports and therefore the one Jellyfin compares against; `flv` is
    /// the decoder's own registered name and shows up in older server builds, so both ship, the same
    /// way DTS is spelled three ways above.
    @Test func offeringThatContainerMeansOfferingItsVideoCodecs() {
        guard list("Container").contains("flv") else { return }
        #expect(list("VideoCodec").isSuperset(of: ["flv1", "flv", "vp6", "vp6f", "vp6a"]))
    }

    @Test func offeringThatContainerMeansOfferingItsAudioCodecs() {
        guard list("Container").contains("flv") else { return }
        #expect(list("AudioCodec").isSuperset(
            of: ["nellymoser", "adpcm_swf", "speex", "pcm_s16be", "pcm_u8", "pcm_alaw", "pcm_mulaw"]))
    }
}
