import Testing
import Foundation
@testable import Sodalite

/// Sodalite#127. Two switches, one per source: the community star and the critic percentage.
/// Both default to ON, so the screen a viewer already knows does not change under them; the
/// point of the setting is that someone who does not want aggregate scores can leave them off
/// for good.
@MainActor
struct RatingVisibilityTests {

    private func defaults(_ name: String) -> UserDefaults {
        let suite = "RatingVisibilityTests.\(name)"
        let store = UserDefaults(suiteName: suite)!
        store.removePersistentDomain(forName: suite)
        return store
    }

    @Test("both scores are shown until someone switches them off")
    func onByDefault() {
        let prefs = AppearancePreferences(store: defaults("defaults"))
        #expect(prefs.showCommunityRating)
        #expect(prefs.showCriticRating)
    }

    @Test("each switch stands alone and survives a relaunch")
    func writeThrough() {
        let store = defaults("persist")
        let prefs = AppearancePreferences(store: store)
        prefs.showCommunityRating = false

        let reloaded = AppearancePreferences(store: store)
        #expect(reloaded.showCommunityRating == false)
        #expect(reloaded.showCriticRating, "the critic switch must not follow the community one")
    }

    @Test("a payload from a build without the switches reads as on, which is what that build drew")
    func absentFieldsReadAsOn() throws {
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
        #expect(payload.showCommunityRating)
        #expect(payload.showCriticRating)
    }

    @Test("both switches ride the payload both ways")
    func roundTrips() throws {
        let payload = AppearanceSettingsPayload(
            updatedAt: Date(timeIntervalSince1970: 1),
            accentChoice: "orange",
            backgroundStyle: "graphiteGlass",
            showContentLogos: true,
            continueWatchingImage: "still",
            largeCards: false,
            nowPlayingUsesSeriesPoster: false,
            showCommunityRating: false,
            showCriticRating: false
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AppearanceSettingsPayload.self, from: data)
        #expect(decoded.showCommunityRating == false)
        #expect(decoded.showCriticRating == false)
    }

    @Test("every place that draws a score reads the switch")
    func drawSitesAreGated() throws {
        for path in [
            "Sodalite/Components/ItemMetadataRow.swift",
            "Sodalite/Features/Detail/CollectionDetailView.swift",
            "Sodalite/Features/Catalog/SeerrMetadataRow.swift",
        ] {
            let source = try sourceFile(path)
            #expect(source.contains("showCommunityRating"), "\(path) draws a star without asking")
            #expect(source.contains("showCriticRating"), "\(path) draws a badge without asking")
        }
    }

    /// A hidden segment must take its separator with it. Both rows place the separator between the
    /// segments that survived, so there is no way to draw a leading or trailing dot.
    @Test("the metadata rows separate segments instead of prefixing them")
    func separatorsSitBetweenSegments() throws {
        for path in [
            "Sodalite/Components/ItemMetadataRow.swift",
            "Sodalite/Features/Catalog/SeerrMetadataRow.swift",
        ] {
            let source = try sourceFile(path)
            #expect(source.contains("if index > 0 { separator }"), "\(path) can draw a leading dot")
            let prefixed = source
                .split(separator: "\n")
                .filter { $0.trimmingCharacters(in: .whitespaces) == "separator" }
            #expect(prefixed.isEmpty, "\(path) still emits a separator ahead of a segment")
        }
    }

    @Test("the critic score is not fetched when it will not be drawn")
    func catalogSkipsTheRoundTrip() throws {
        let source = try sourceFile("Sodalite/Features/Catalog/CatalogDetailView.swift")
        #expect(source.contains("showCriticRating"))
    }

    @Test("both rows are wired into the appearance toggles section")
    func rowsPresent() throws {
        let source = try sourceFile("Sodalite/Features/Support/AppearanceSettingsView.swift")
        #expect(source.contains("settings.appearance.communityRating"))
        #expect(source.contains("settings.appearance.criticRating"))
        #expect(source.contains("appearance.showCommunityRating"))
        #expect(source.contains("appearance.showCriticRating"))
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
