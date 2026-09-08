import Testing
import Foundation
import SwiftUI
@testable import Sodalite

/// Sodalite#99 replaced a 10pt full-bleed bar with an inset capsule plus a remaining-time label.
/// What is pinned here is the intent: the row is a fraction of the tier's poster width like every
/// other artwork overlay, it never draws on a finished item, and the label only exists where there
/// is a real resume point to measure from.
@MainActor
struct ResumeCapsuleTests {

    private let tiers: [(name: String, metrics: LayoutMetrics)] = [
        ("tvOS", .tv), ("iPad", .regular), ("iPhone", .compact),
    ]
    /// The Appearance setting is a switch, not a slider: normal cards or large ones.
    private let scales: [CGFloat] = [1.0, AppearancePreferences.largeCardScale]

    private func decodeItem(_ json: String) throws -> JellyfinItem {
        try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
    }

    // MARK: - Geometry

    /// The whole point of sizing off the poster width: a landscape card and the poster beside it
    /// wear the same row, and the setting moves both.
    @Test func everyMetricTracksTheCardScale() {
        let width = LayoutMetrics.tv.posterSize.width
        for metric in [PosterBadgeMetrics.checkInset, PosterBadgeMetrics.trackHeight,
                       PosterBadgeMetrics.labelGap, PosterBadgeMetrics.remainingLabelSize] {
            #expect(metric(width, AppearancePreferences.largeCardScale) > metric(width, 1.0))
        }
    }

    /// The band this replaces was a fixed 10pt, which is 4.5 percent of a TV poster and 8.3 percent
    /// of a phone one: heaviest exactly where there is least room. Every tier now lands in the same
    /// narrow band instead.
    @Test func theCapsuleKeepsOneWeightAcrossTiers() {
        for tier in tiers {
            let width = tier.metrics.posterSize.width
            let ratio = PosterBadgeMetrics.trackHeight(posterWidth: width, scale: 1) / width
            #expect(ratio >= 0.025 && ratio <= 0.035, "\(tier.name) capsule is \(ratio * 100)% of the poster")
        }
    }

    /// A hairline is not a meter. The floor is what keeps the smallest tier honest.
    @Test func theCapsuleNeverFallsBelowItsFloor() {
        for tier in tiers {
            for scale in scales {
                let height = PosterBadgeMetrics.trackHeight(posterWidth: tier.metrics.posterSize.width, scale: scale)
                #expect(height >= 3, "\(tier.name) at \(scale) is \(height)pt")
            }
        }
    }

    /// The label sits beside a meter with nothing behind it, so it is deliberately smaller than the
    /// quality pills, which carry their own scrim. Rendered side by side, 0.09 dominated the poster.
    @Test func theLabelIsSmallerThanThePills() {
        for tier in tiers {
            let width = tier.metrics.posterSize.width
            let label = PosterBadgeMetrics.remainingLabelSize(posterWidth: width, scale: 1)
            let pill = PosterBadgeMetrics.fontSize(posterWidth: width, scale: 1)
            #expect(label < pill)
            #expect(label / width >= 0.07, "\(tier.name) label is \(label / width * 100)% of the poster")
        }
    }

    /// The guard that drops the label. It is a share of the card, so it holds at both card scales
    /// without a second number: every term of the row scales together.
    @Test func theGuardLeavesTheMeterMoreThanAThirdOfTheCard() {
        #expect(PosterBadgeMetrics.minimumTrackShare > 0.3)
        #expect(PosterBadgeMetrics.minimumTrackShare < 0.5)
        for tier in tiers {
            let width = tier.metrics.posterSize.width
            for scale in scales {
                let minimum = width * PosterBadgeMetrics.minimumTrackShare * scale
                let available = width * scale - 2 * PosterBadgeMetrics.checkInset(posterWidth: width, scale: scale)
                #expect(minimum < available, "\(tier.name) at \(scale) cannot fit its own minimum")
            }
        }
    }

    // MARK: - When the row is drawn

    /// The defect: a finished item drew a full bar AND the watched check, one state twice. It shows
    /// up without a server round-trip, because `setResumePosition` writes both past the threshold.
    @Test func aFinishedItemDrawsNothing() throws {
        var item = try decodeItem(#"{"Id":"m","Name":"M","Type":"Movie","RunTimeTicks":1000}"#)
        item.setResumePosition(1000)
        #expect(item.userData?.played == true)
        #expect(item.userData?.playedPercentage == 100)
        #expect(ResumeIndicator.fraction(playedPercentage: item.userData?.playedPercentage,
                                         isPlayed: item.userData?.played == true,
                                         playbackPositionTicks: item.userData?.playbackPositionTicks) == nil)
    }

    @Test func anUntouchedItemDrawsNothing() {
        #expect(ResumeIndicator.fraction(playedPercentage: nil, isPlayed: false, playbackPositionTicks: 5) == nil)
        #expect(ResumeIndicator.fraction(playedPercentage: 0, isPlayed: false, playbackPositionTicks: 5) == nil)
    }

    /// A container carries a percentage that counts its CHILDREN, never a resume position, and the
    /// bar means "you are partway through this one thing". Drawing it on a series poster advertises
    /// a resume point that does not exist: #99 said as much when it excluded music albums on exactly
    /// this ground, but the exclusion never reached the code, so every favourited series wore a
    /// capsule for the share of its episodes watched (Sodalite#135).
    @Test func aContainerDrawsNothing() throws {
        let series = try decodeItem(#"{"Id":"s","Name":"S","Type":"Series","UserData":{"PlayedPercentage":85,"Played":false}}"#)
        #expect(series.userData?.playedPercentage == 85)
        #expect(series.userData?.playbackPositionTicks == nil)
        #expect(ResumeIndicator.fraction(playedPercentage: series.userData?.playedPercentage,
                                         isPlayed: series.userData?.played == true,
                                         playbackPositionTicks: series.userData?.playbackPositionTicks) == nil)
    }

    /// The episode card always carries progress, whatever the setting says: it shows the thing being
    /// watched. The poster is the opt-in half (Sodalite#136).
    @Test func theEpisodeCardAlwaysCarriesProgress() {
        #expect(MediaCardStyle.landscape.showsResumeProgress(posterProgressEnabled: false))
        #expect(MediaCardStyle.landscape.showsResumeProgress(posterProgressEnabled: true))
    }

    @Test func thePosterCarriesProgressOnlyWhenAskedTo() {
        #expect(!MediaCardStyle.poster.showsResumeProgress(posterProgressEnabled: false))
        #expect(MediaCardStyle.poster.showsResumeProgress(posterProgressEnabled: true))
    }

    /// The album card stays out of it in both positions: a container has no resume point to draw,
    /// so an opt-in that reached it would promise something the data cannot answer (Sodalite#135).
    @Test func theAlbumCardNeverCarriesProgress() {
        #expect(!MediaCardStyle.square.showsResumeProgress(posterProgressEnabled: false))
        #expect(!MediaCardStyle.square.showsResumeProgress(posterProgressEnabled: true))
    }

    @Test func aStartedItemDrawsItsShare() {
        #expect(ResumeIndicator.fraction(playedPercentage: 42, isPlayed: false, playbackPositionTicks: 420) == 0.42)
        #expect(ResumeIndicator.fraction(playedPercentage: 140, isPlayed: false, playbackPositionTicks: 999) == 1)
    }

    // MARK: - The label

    /// A series or an album carries a percentage that counts children, never a resume position.
    /// Subtracting the missing position from the runtime would have advertised a whole album as
    /// left to play.
    @Test func aContainerItemGetsNoLabel() throws {
        let album = try decodeItem(#"""
        {"Id":"a","Name":"A","Type":"MusicAlbum","RunTimeTicks":24000000000,
         "UserData":{"PlayedPercentage":60}}
        """#)
        #expect(album.userData?.playedPercentage == 60)
        #expect(album.resumeRemainingTicks == nil)
    }

    @Test func aStartedItemGetsItsRemainder() throws {
        // 60 minutes long, 20 in.
        let item = try decodeItem(#"""
        {"Id":"m","Name":"M","Type":"Movie","RunTimeTicks":36000000000,
         "UserData":{"PlaybackPositionTicks":12000000000,"PlayedPercentage":33.3}}
        """#)
        #expect(item.resumeRemainingTicks == 24_000_000_000)
    }

    /// Under a minute there is nothing worth saying, and the formatter would round it up to "1m",
    /// which is the one number that is definitely wrong.
    @Test func aRemainderUnderAMinuteGetsNoLabel() throws {
        let item = try decodeItem(#"""
        {"Id":"m","Name":"M","Type":"Movie","RunTimeTicks":36000000000,
         "UserData":{"PlaybackPositionTicks":35999000000,"PlayedPercentage":99.9}}
        """#)
        #expect(item.resumeRemainingTicks == nil)
    }

    @Test func anItemWithoutARuntimeGetsNoLabel() throws {
        let item = try decodeItem(#"""
        {"Id":"s","Name":"S","Type":"Series","UserData":{"PlaybackPositionTicks":12000000000}}
        """#)
        #expect(item.resumeRemainingTicks == nil)
    }

    /// The reason the label uses CLDR's narrow units instead of the catalogue's own suffixes: in the
    /// languages that spell them out (de "Std."/"Min.", pl "godz.") our form is half again as wide
    /// as narrow at the same size, which is the difference between a label that fits beside the
    /// meter on a phone poster and one the guard drops. Narrow is never the longer of the two.
    @Test func theCompactFormIsNeverLongerThanTheMetadataForm() {
        for minutes in [1, 23, 59, 60, 61, 108, 228] {
            let ticks = Int64(minutes) * 60 * 10_000_000
            #expect(ticks.ticksToCompactDisplay.count <= ticks.ticksToDisplay.count,
                    "\(minutes)m: \(ticks.ticksToCompactDisplay) vs \(ticks.ticksToDisplay)")
            #expect(!ticks.ticksToCompactDisplay.isEmpty)
        }
    }
}
