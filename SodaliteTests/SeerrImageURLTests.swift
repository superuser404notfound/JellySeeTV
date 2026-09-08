import Foundation
import Testing
@testable import Sodalite

struct SeerrImageURLTests {
    /// TMDB has no profile rendition between w185 and h632, so the picker has exactly one step.
    @Test func profileSizeCoversRequestedPixels() {
        #expect(SeerrImageURL.ProfileSize.covering(185) == .w185)
        #expect(SeerrImageURL.ProfileSize.covering(186) == .h632)
        #expect(SeerrImageURL.ProfileSize.covering(LayoutMetrics.tv.castImageWidth) == .h632)
        #expect(SeerrImageURL.ProfileSize.covering(LayoutMetrics.compact.castImageWidth) == .h632)
    }

    @Test func profileURLUsesChosenRendition() {
        let url = SeerrImageURL.profile(path: "/abc.jpg", size: .h632)
        #expect(url?.absoluteString == "https://image.tmdb.org/t/p/h632/abc.jpg")
    }

    @Test func profileURLIsNilWithoutPath() {
        #expect(SeerrImageURL.profile(path: nil) == nil)
        #expect(SeerrImageURL.profile(path: "") == nil)
    }
}

extension SeerrImageURLTests {

    /// TMDB's poster buckets, in pixels, so the assertions below read as widths rather than as
    /// case names.
    private static func pixels(_ size: SeerrImageURL.PosterSize) -> Int {
        switch size {
        case .w342: 342
        case .w500: 500
        case .w780: 780
        }
    }

    /// The 16:9 tiles grew with Large Cards, so w780 stopped covering them.
    @Test func backdropCoveringClearsTheWidestTile() {
        let m = LayoutMetrics.tv
        let rendered = m.landscapeSize.width * AppearancePreferences.largeCardScale * m.screenScale
        #expect(SeerrImageURL.BackdropSize.covering(ImageWidth.wideCard) == .w1280)
        #expect(CGFloat(1280) >= rendered)
        #expect(CGFloat(780) < rendered)
        #expect(SeerrImageURL.BackdropSize.covering(700) == .w780)
    }

    @Test func posterCoveringTakesTheSmallestRenditionThatFits() {
        #expect(SeerrImageURL.PosterSize.covering(300) == .w342)
        #expect(SeerrImageURL.PosterSize.covering(342) == .w342)
        #expect(SeerrImageURL.PosterSize.covering(343) == .w500)
        #expect(SeerrImageURL.PosterSize.covering(500) == .w500)
        #expect(SeerrImageURL.PosterSize.covering(501) == .w780)
    }

    /// The reason the card asks by width instead of taking the default: a Seerr poster at Large
    /// Cards on tvOS is 572px, which w500 does not reach.
    @Test func theSeerrCardRenditionCoversItsWidestRender() {
        let m = LayoutMetrics.tv
        let rendered = m.posterSize.width * AppearancePreferences.largeCardScale * m.screenScale
        let chosen = SeerrImageURL.PosterSize.covering(ImageWidth.card)
        #expect(CGFloat(Self.pixels(chosen)) >= rendered)
        #expect(Self.pixels(.w500) < Int(rendered))
    }
}
