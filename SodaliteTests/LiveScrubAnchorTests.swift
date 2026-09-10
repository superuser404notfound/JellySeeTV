import Testing
import Foundation
@testable import Sodalite

/// Sodalite#104, round 3: a rewind on live snapped straight back to live.
///
/// Two decisions were reading the same number and neither was wrong on its own.
///
/// `scrubReferenceDuration` is the DVR WINDOW for a live session, so a scrub position is a fraction
/// of the window and a skip interval is a tiny slice of it: 10 s of a 30 minute window is 0.0056.
/// The commit then asked whether that fraction was `>= 0.99` and treated it as "scrubbed fully
/// right, snap to live". But 0.99 of a window is not a distance from live. It is 18 s on a 30
/// minute window, 1.2 s on a two minute one, and 6 s on the ten minute one in between. The rule
/// changes meaning with the DVR depth, which is the same defect class as the edge tolerance this
/// issue started with: a constant answering a question whose unit is seconds.
///
/// Round 2 then made it fire every time. Pinning the view model's `progress` to 1 at the live edge
/// was right for the RAIL and wrong for the ANCHOR: `seekJump` seeds `scrubProgress` from
/// `progress`, so every rewind started at exactly 1.0, and a 10 s press landed at 0.994, still
/// inside the 1% and therefore committed as a return to live. The picture never moved.
///
/// So the anchor is the honest fraction again, and the snap is the right STOP: a scrub that has
/// been pushed to the end of the rail, which is the affordance the bar actually offers.
@Suite("The live scrub anchor and the snap rule (Sodalite#104)")
struct LiveScrubAnchorTests {

    /// The reported shape: a 30 minute DVR window, the playhead at the live edge.
    private let window: ClosedRange<Double> = 0...1800

    @Test("the anchor is the playhead, not the verdict")
    func anchorIsThePlayhead() {
        // 4 s behind the edge, which is where a healthy live client sits between two cuts.
        let anchor = PlayerViewModel.liveScrubAnchor(currentTime: 1796, range: window)
        #expect(abs(anchor - 0.9978) < 0.001)
        #expect(anchor < 1)
    }

    @Test("a 10 s rewind from the live edge does not read as a return to live")
    func aShortRewindIsARewind() {
        let anchor = PlayerViewModel.liveScrubAnchor(currentTime: 1800, range: window)
        let afterOnePress = anchor - Float(10.0 / 1800.0)
        #expect(!PlayerViewModel.liveScrubReachedLiveEdge(scrubProgress: afterOnePress))
        // The old rule swallowed it whole: 0.994 is above 0.99.
        #expect(afterOnePress > 0.99)
    }

    @Test("the same press on a short window behaved differently, which was the tell")
    func theOldRuleChangedMeaningWithTheWindow() {
        // Two minutes of DVR: 10 s is 8% of the rail, so the old rule let it through, while the
        // same press on a 30 minute window did not move the picture at all.
        let short: ClosedRange<Double> = 0...120
        let anchor = PlayerViewModel.liveScrubAnchor(currentTime: 120, range: short)
        let afterOnePress = anchor - Float(10.0 / 120.0)
        #expect(afterOnePress < 0.99)
        #expect(!PlayerViewModel.liveScrubReachedLiveEdge(scrubProgress: afterOnePress))
    }

    @Test("pushing the knob to the right stop is still the return-to-live affordance")
    func theRightStopStillSnaps() {
        #expect(PlayerViewModel.liveScrubReachedLiveEdge(scrubProgress: 1))
        // scrubProgress is clamped to 0...1 at every writer, so the stop is exact.
        #expect(PlayerViewModel.liveScrubReachedLiveEdge(scrubProgress: 1.0001))
        #expect(!PlayerViewModel.liveScrubReachedLiveEdge(scrubProgress: 0.995))
    }

    @Test("the rail still pins at the edge while the anchor stays honest")
    func railAndAnchorAnswerDifferentQuestions() {
        // The pair that has to hold: the knob sits at the end while LIVE shows, and a scrub that
        // starts there begins from where the playhead really is.
        #expect(PlayerViewModel.liveRailProgress(
            currentTime: 1796, range: window, isAtLiveEdge: true) == 1)
        #expect(PlayerViewModel.liveScrubAnchor(currentTime: 1796, range: window) < 1)
    }

    @Test("a degenerate window anchors at the start rather than dividing by zero")
    func aDegenerateWindowIsSafe() {
        #expect(PlayerViewModel.liveScrubAnchor(currentTime: 5, range: 5...5) == 0)
    }
}
