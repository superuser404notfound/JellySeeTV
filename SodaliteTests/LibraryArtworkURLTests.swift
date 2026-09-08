import Foundation
import Testing
@testable import Sodalite

/// Sodalite#84. The My Media tile paints the library's own artwork and only falls back to the
/// generic icon when the server has none, so what these pin is the fallback order: a library with
/// artwork must never resolve to nil, and a library without one must never resolve to a URL that
/// would 404 into an empty tile.
struct LibraryArtworkURLTests {
    private let service = JellyfinImageService(baseURLProvider: { URL(string: "https://jf.test") })

    private func library(primary: String? = nil, thumb: String? = nil) -> JellyfinLibrary {
        JellyfinLibrary(
            id: "lib1",
            name: "Movies",
            collectionType: "movies",
            imageTags: ImageTags(primary: primary, backdrop: nil, thumb: thumb, logo: nil, banner: nil)
        )
    }

    @Test("a library with a Primary image resolves to it")
    func primaryImage() throws {
        let url = try #require(service.libraryArtworkURL(for: library(primary: "p1")))
        #expect(url.path == "/Items/lib1/Images/Primary")
        #expect(url.query?.contains("tag=p1") == true)
        #expect(url.query?.contains("maxWidth=\(ImageWidth.wideCard)") == true)
    }

    @Test("Primary wins over Thumb when the library carries both")
    func primaryBeatsThumb() throws {
        let url = try #require(service.libraryArtworkURL(for: library(primary: "p1", thumb: "t1")))
        #expect(url.path == "/Items/lib1/Images/Primary")
        #expect(url.query?.contains("tag=p1") == true)
    }

    @Test("a Thumb-only library falls back to Thumb rather than the generic tile")
    func thumbFallback() throws {
        let url = try #require(service.libraryArtworkURL(for: library(thumb: "t1")))
        #expect(url.path == "/Items/lib1/Images/Thumb")
        #expect(url.query?.contains("tag=t1") == true)
    }

    @Test("a library without artwork resolves to nil, which is what shows the generic tile")
    func noArtwork() {
        #expect(service.libraryArtworkURL(for: library()) == nil)
        #expect(service.libraryArtworkURL(
            for: JellyfinLibrary(id: "lib2", name: "Shows", collectionType: "tvshows", imageTags: nil)
        ) == nil)
    }
}

/// Sodalite#84 round two: the name is drawn over library artwork only on request, because most
/// library images have that name burnt in already. What these pin is the default and the reading of
/// a payload that predates the switch, both of which have to mean "do not draw it".
@MainActor
struct LibraryNameOverlaySettingTests {

    private func scratchDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "libraryNames.\(name)")!
        defaults.removePersistentDomain(forName: "libraryNames.\(name)")
        return defaults
    }

    @Test("the name stays off the artwork until someone asks for it")
    func offByDefault() {
        #expect(AppearancePreferences(store: scratchDefaults("default")).showLibraryNames == false)
    }

    @Test("the switch survives a relaunch")
    func survivesRelaunch() {
        let defaults = scratchDefaults("persist")
        AppearancePreferences(store: defaults).showLibraryNames = true
        #expect(AppearancePreferences(store: defaults).showLibraryNames)
    }

    @Test("a payload from a build without the switch reads as off, which is what that build drew")
    func absentFieldReadsAsOff() throws {
        let json = """
        {
          "schemaVersion": 4,
          "updatedAt": 0,
          "accentChoice": "orange",
          "backgroundStyle": "graphiteGlass",
          "showContentLogos": true,
          "continueWatchingImage": "still",
          "largeCards": false,
          "nowPlayingUsesSeriesPoster": false
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let payload = try decoder.decode(AppearanceSettingsPayload.self, from: Data(json.utf8))
        #expect(payload.showLibraryNames == false)
    }

    @Test("the switch rides the payload both ways")
    func roundTrips() throws {
        let payload = AppearanceSettingsPayload(
            updatedAt: Date(timeIntervalSince1970: 1),
            accentChoice: "orange",
            backgroundStyle: "graphiteGlass",
            showContentLogos: true,
            continueWatchingImage: "still",
            largeCards: false,
            nowPlayingUsesSeriesPoster: false,
            showLibraryNames: true
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AppearanceSettingsPayload.self, from: data)
        #expect(decoded.showLibraryNames)
    }
}
