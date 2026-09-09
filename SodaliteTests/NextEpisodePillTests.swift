import Testing
import Foundation
import SwiftUI
@testable import Sodalite

/// Sodalite#103 turned the next-episode card into a pill that wears the skip hint's chrome, with the
/// countdown as a ring and the episode metadata on a line above it.
///
/// What is pinned here is the intent, not the pixels: the two pills stay one treatment, the countdown
/// costs the pill neither width nor height, and the pill's width is decided by the widest LOCALIZED
/// label rather than the English one.
@MainActor
struct NextEpisodePillTests {

    private let tiers: [(name: String, metrics: PlayerPillMetrics)] = [
        ("tvOS", .tv), ("touch", .touch),
    ]

    // MARK: - Geometry

    /// The whole reason the countdown became a ring: it sits in the glyph slot the skip pill already
    /// fills, so a pill with a countdown and one without are the same height, and so are the two
    /// pills next to each other across an episode seam.
    @Test func theCountdownCostsThePillNoHeight() {
        for tier in tiers {
            #expect(tier.metrics.ringDiameter == tier.metrics.labelLineHeight,
                    "\(tier.name) ring is \(tier.metrics.ringDiameter) against a \(tier.metrics.labelLineHeight)pt line")
            #expect(tier.metrics.pillHeight == tier.metrics.labelLineHeight + tier.metrics.verticalPadding * 2)
        }
    }

    /// A label sized off English is the trap the original proposal fell into: "Next Episode" is 265pt
    /// on tvOS, ru "Следующий эпизод" is 367pt. The frame has to hold the widest one, in every locale
    /// shipped, or the pill truncates its own action.
    @Test func theFrameHoldsTheWidestLocalizedLabel() throws {
        let catalog = try catalogEntries()
        for tier in tiers {
            for key in ["player.nextEpisode", "player.upNext"] {
                for (locale, value) in try catalog(key) {
                    let width = labelWidth(value, tier: tier.metrics)
                    #expect(width <= tier.metrics.stackWidth,
                            "\(tier.name) \(locale) \"\(value)\" needs \(width)pt of \(tier.metrics.stackWidth)pt")
                }
            }
        }
    }

    /// The metadata line is the part that may be read, the pill is the part that gets pressed. It
    /// stays the lighter of the two, or the prompt reads as a caption with a button under it.
    @Test func theMetadataLineIsQuieterThanTheLabel() {
        for tier in tiers {
            #expect(tier.metrics.metadataSize <= tier.metrics.labelSize,
                    "\(tier.name) metadata \(tier.metrics.metadataSize) against label \(tier.metrics.labelSize)")
        }
    }

    /// The stack is positioned absolutely (the AVKit teardown collapses the SwiftUI parent for
    /// ~100 ms at exactly this moment), so its height has to be computable without laying it out.
    @Test func theStackHeightIsTheSumOfItsParts() {
        for tier in tiers {
            #expect(tier.metrics.stackHeight
                    == tier.metrics.metadataLineHeight + tier.metrics.stackSpacing + tier.metrics.pillHeight)
            // The card this replaces was 214pt tall on tvOS. Anything approaching that has drifted
            // back into being a card.
            #expect(tier.metrics.stackHeight < 150, "\(tier.name) stack is \(tier.metrics.stackHeight)pt")
        }
    }

    // MARK: - Countdown ring

    /// The ring is a fraction of what the countdown STARTED from, not of a fixed ten: the length is a
    /// user setting (Sodalite#67) and the no-outro fallback passes the real remaining seconds, and
    /// both have to drain exactly one turn.
    ///
    /// What each tick publishes is where the arc must ARRIVE, not where it stands, because the trim
    /// is animated linearly across the second that follows. Publishing the tick's own fraction drew
    /// the ring a whole second behind the countdown: it sat full through the arrival animation
    /// instead of draining from the moment it appeared, and at the switch it still carried one
    /// second of arc. Reported on device, 2026-09-09.
    @Test func everyTickTargetsTheFractionItEndsOn() throws {
        for total in [3, 5, 10, 30, 120] {
            for remaining in 1...total {
                let target = try #require(NextEpisodeCountdown.ringTarget(remaining: remaining, total: total))
                #expect(abs(target - Double(remaining - 1) / Double(total)) < 1e-9)
            }
        }
    }

    /// The arc leaves a full turn on the first tick. The trim reads 1 while there is no ring, so the
    /// arrival animates from full down by one tick's share, which is the countdown draining rather
    /// than a ring that pops up complete and waits.
    @Test func theArcLeavesFullOnTheFirstTick() throws {
        let target = try #require(NextEpisodeCountdown.ringTarget(remaining: 15, total: 15))
        #expect(abs(target - 14.0 / 15.0) < 1e-9)
    }

    /// The last tick lands on empty, which is the frame the viewer sees at the switch. Zero, not nil:
    /// nil means there is no countdown at all and takes the ring off the glyph a second early.
    @Test func theLastTickLandsOnEmpty() throws {
        #expect(NextEpisodeCountdown.ringTarget(remaining: 1, total: 30) == 0)
        #expect(NextEpisodeCountdown.ringTarget(remaining: 1, total: 1) == 0)
    }

    /// nil, not zero: no countdown means no ring at all, and the glyph then takes the space the ring
    /// would have used. Autoplay off, countdown off and the PiP advance all land here.
    @Test func noCountdownDrawsNoRing() {
        #expect(NextEpisodeCountdown.ringTarget(remaining: 0, total: 10) == nil)
        #expect(NextEpisodeCountdown.ringTarget(remaining: 10, total: 0) == nil)
        #expect(NextEpisodeCountdown.ringTarget(remaining: -1, total: 10) == nil)
    }

    /// A total that has drifted below the remaining seconds (a countdown restarted shorter than the
    /// one it replaced) must not overdraw the ring past a full turn.
    @Test func theRingNeverExceedsAFullTurn() {
        #expect(NextEpisodeCountdown.ringTarget(remaining: 30, total: 10) == 1)
    }

    /// `play.fill` is centred on its layout box, so inside a ring it reads left of centre: a
    /// right-pointing triangle's mass sits at its base. Measured against Apple's own
    /// `play.circle.fill`, whose triangle box sits at +0.033 of the disc diameter, ours was at
    /// +0.008 on the device. The nudge closes that, and only that, so a value outside this band is
    /// somebody retuning by eye rather than against the symbol.
    @Test func theRingGlyphIsNudgedOffItsLayoutBox() throws {
        let pill = try sourceFile("Sodalite/Player/UI/PlayerActionPill.swift")
        #expect(pill.contains("diameter * 0.025"))
        #expect(pill.contains(".offset(x: glyphNudge)"))
        // Without a ring the glyph stays as SF ships it, matching the skip pill beside it.
        #expect(pill.contains("hasRing ? diameter * 0.025 : 0"))
    }

    /// The metadata rides as an overlay on the pill rather than as a sibling in a stack, because a
    /// stack sizes to the wider of the two: the pill would leave the trailing margin by half the
    /// title's overhang, and by a different amount every episode. The two pills share that margin,
    /// which is the whole point of the issue.
    @Test func theMetadataCannotMoveThePillOffItsAnchor() throws {
        let pill = try sourceFile("Sodalite/Player/UI/PlayerActionPill.swift")
        #expect(pill.contains(".overlay(alignment: .top)"))
        #expect(pill.contains("alignment: .bottomTrailing"))
        // An episode name is not shortened to keep the line centred. It centres on the button while
        // it fits the button plus its overhang, and slides LEFT past that, into empty video rather
        // than into the screen edge. Only the far margin can still cut a name off.
        #expect(pill.contains("private var lineOffset: CGFloat"))
        #expect(pill.contains("min(lineWidth, metadataMaxWidth)"))
        for tier in tiers {
            #expect(tier.metrics.metadataOverhang * 2 <= tier.metrics.marginX,
                    "\(tier.name) overhang \(tier.metrics.metadataOverhang) against margin \(tier.metrics.marginX)")
        }
        // The declared height has to be enforced, or the absolute .position in the overlay measures
        // the pill alone and the prompt sits high by half the metadata line.
        #expect(pill.contains("height: metrics.stackHeight"))
    }

    /// "The same corner" is the issue's actual complaint, so the anchor is one number both pills
    /// read rather than two literals that happen to agree. They were 24/28 and 80/80 inline.
    @Test func bothPillsAnchorToTheSameCorner() throws {
        let overlay = try sourceFile("Sodalite/Player/UI/PlayerOverlayView.swift")
        #expect(overlay.contains("PlayerPillMetrics.current.marginX"))
        #expect(overlay.contains("PlayerPillMetrics.current.marginY"))
        #expect(overlay.contains("let marginX = metrics.marginX"))
    }

    // MARK: - One treatment, not two

    /// The point of the issue: both pills draw from one chrome. A second inline capsule in the
    /// overlay means the drift is back.
    @Test func bothPillsDrawFromTheSharedChrome() throws {
        let overlay = try sourceFile("Sodalite/Player/UI/PlayerOverlayView.swift")
        let pill = try sourceFile("Sodalite/Player/UI/PlayerActionPill.swift")
        #expect(overlay.contains("playerGlassPill()"))
        // The chrome is five literals that used to sit inline. They live in one file now, and a
        // second copy in the overlay is the drift this issue is about.
        for literal in [".white.opacity(0.35)", "radius: 14, y: 6"] {
            #expect(pill.contains(literal))
            #expect(!overlay.contains(literal), "\(literal) is back in PlayerOverlayView")
        }
        // The light-mode bug this fixes on the way past: the card was the only glass surface in the
        // player that did not pin dark, under text hardcoded white.
        #expect(!overlay.contains(".background(.thinMaterial)"))
        #expect(pill.contains("environment(\\.colorScheme, .dark)"))
    }

    /// The hint that only existed because a card with no countdown said nothing about being
    /// pressable. A capsule with a play glyph says it itself, so the strings go too.
    @Test func thePlayNowHintIsGone() throws {
        let overlay = try sourceFile("Sodalite/Player/UI/PlayerOverlayView.swift")
        #expect(!overlay.contains("playNowHint"))
        let catalog = try catalogKeys()
        for key in ["player.nextEpisode.clickToPlay", "player.nextEpisode.tapToPlay",
                    "player.nextEpisode.countdown %lld"] {
            #expect(!catalog.contains(key), "\(key) is still in the catalog")
        }
    }

    // MARK: - Helpers

    private func labelWidth(_ label: String, tier: PlayerPillMetrics) -> CGFloat {
        let font = UIFont.systemFont(ofSize: tier.labelSize, weight: .semibold)
        let text = (label as NSString).size(withAttributes: [.font: font]).width
        return text + tier.horizontalPadding * 2 + tier.ringDiameter + tier.iconSpacing
    }

    private func catalogKeys() throws -> Set<String> {
        let raw = try sourceFile("Sodalite/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        let strings = json?["strings"] as? [String: Any] ?? [:]
        return Set(strings.keys)
    }

    private func catalogEntries() throws -> (String) throws -> [(String, String)] {
        let raw = try sourceFile("Sodalite/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        let strings = json?["strings"] as? [String: Any] ?? [:]
        return { key in
            guard let entry = strings[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { return [] }
            return localizations.compactMap { locale, value in
                guard let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any],
                      let string = unit["value"] as? String else { return nil }
                return (locale, string)
            }
        }
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repository.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
