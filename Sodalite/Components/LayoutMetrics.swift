import SwiftUI

/// Platform + size-class layout knobs for the browse UI. tvOS (10-foot) keeps its
/// large values; iPad regular gets a middle tier; iPhone compact gets phone scale.
/// Card sizes are pre-cardScale; callers still multiply by appearancePreferences.cardScale.
struct LayoutMetrics: Equatable {
    var posterSize: CGSize
    /// Also the size of every 16:9 tile that is not a MediaCard (genre, provider, library):
    /// one width for the whole family, so those rows line up with a landscape media row.
    var landscapeSize: CGSize
    var squareSize: CGSize
    /// Thumbnail in the vertical detail lists (collection, playlist, watch stats).
    /// tvOS reads these from the couch, so it gets a share of the browse poster
    /// rather than the touch-scale thumb.
    var listPosterSize: CGSize
    var listTitleFont: Font
    var listOverviewFont: Font
    var rowInset: CGFloat
    var itemSpacing: CGFloat
    var rowVerticalPadding: CGFloat
    var gridMinimum: CGFloat
    var gridSpacing: CGFloat
    var gridInset: CGFloat
    var screenHInset: CGFloat
    var screenVInset: CGFloat
    var profileCardSize: CGSize
    /// Cast portrait diameter and the label column under it. These are separate because tvOS
    /// text styles are roughly double the phone's (caption1 25pt vs 12pt), so a single shared
    /// card width fits 15 characters on a phone and 8 on a TV (Sodalite#55).
    var castPortrait: CGFloat
    var castLabelWidth: CGFloat
    /// Pixel width to request for the portrait: diameter times the tier's screen scale
    /// (tvOS 4K renders 2x, iPhone 3x), so enlarging the circle can't leave the source behind.
    var castImageWidth: Int
    /// Pixels per point the tier's device draws at, and the ceiling where a family spans several
    /// devices: every iPad is 2x, iPhones are 2x or 3x, so the compact tier takes 3. It is what
    /// turns a point size here into the pixels to ask the server for, which is how `ImageWidth`
    /// is cut and what `ImageWidthTests` recomputes (Sodalite#129).
    var screenScale: CGFloat

    func size(for style: MediaCardStyle) -> CGSize {
        switch style {
        case .poster: posterSize
        case .landscape: landscapeSize
        case .square: squareSize
        }
    }

    /// tvOS 10-foot tier: the current shipped values (keeps tvOS byte-identical).
    static let tv = LayoutMetrics(
        posterSize: CGSize(width: 220, height: 330),
        landscapeSize: CGSize(width: 360, height: 202),
        squareSize: CGSize(width: 220, height: 220),
        listPosterSize: CGSize(width: 140, height: 210),
        listTitleFont: .title3, listOverviewFont: .footnote,
        rowInset: 50, itemSpacing: 30, rowVerticalPadding: 20,
        gridMinimum: 220, gridSpacing: 40, gridInset: 60,
        screenHInset: 80, screenVInset: 60,
        profileCardSize: CGSize(width: 180, height: 180),
        castPortrait: 180, castLabelWidth: 220, castImageWidth: 400,
        screenScale: 2
    )
    /// iPad regular tier.
    static let regular = LayoutMetrics(
        posterSize: CGSize(width: 160, height: 240),
        landscapeSize: CGSize(width: 280, height: 158),
        squareSize: CGSize(width: 160, height: 160),
        listPosterSize: CGSize(width: 80, height: 120),
        listTitleFont: .body, listOverviewFont: .caption,
        rowInset: 28, itemSpacing: 20, rowVerticalPadding: 16,
        gridMinimum: 160, gridSpacing: 28, gridInset: 24,
        screenHInset: 40, screenVInset: 32,
        profileCardSize: CGSize(width: 160, height: 160),
        castPortrait: 120, castLabelWidth: 140, castImageWidth: 300,
        screenScale: 2
    )
    /// iPhone compact tier.
    static let compact = LayoutMetrics(
        posterSize: CGSize(width: 120, height: 180),
        landscapeSize: CGSize(width: 200, height: 112),
        squareSize: CGSize(width: 120, height: 120),
        listPosterSize: CGSize(width: 80, height: 120),
        listTitleFont: .body, listOverviewFont: .caption,
        rowInset: 16, itemSpacing: 12, rowVerticalPadding: 12,
        gridMinimum: 108, gridSpacing: 16, gridInset: 16,
        screenHInset: 16, screenVInset: 16,
        profileCardSize: CGSize(width: 120, height: 120),
        castPortrait: 100, castLabelWidth: 100, castImageWidth: 300,
        screenScale: 3
    )

    /// Platform-independent selector (testable on any target).
    static func metrics(compact: Bool, isTV: Bool) -> LayoutMetrics {
        if isTV { return .tv }
        return compact ? .compact : .regular
    }

    /// Resolves the tier for the current platform + size class.
    static func current(_ sizeClass: UserInterfaceSizeClass?) -> LayoutMetrics {
        #if os(tvOS)
        return metrics(compact: false, isTV: true)
        #else
        return metrics(compact: sizeClass == .compact, isTV: false)
        #endif
    }
}
