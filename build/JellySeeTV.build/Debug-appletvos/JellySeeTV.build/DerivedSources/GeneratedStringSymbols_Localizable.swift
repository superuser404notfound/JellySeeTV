// 
// GeneratedStringSymbols_Localizable.swift
// Auto-Generated symbols for localized strings defined in “Localizable.xcstrings”.
// 

import Foundation

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private nonisolated let resourceBundleDescription = LocalizedStringResource.BundleDescription.atURL(resourceBundle.bundleURL)
#else

private class ResourceBundleClass {}
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private nonisolated let resourceBundleDescription = LocalizedStringResource.BundleDescription.forClass(ResourceBundleClass.self)
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
nonisolated extension LocalizedStringResource {
    /**
     Placeholder for the password field
     
     Localized string for key “auth.login.password” in table “Localizable.xcstrings”.
     */
    static var authLoginPassword: LocalizedStringResource {
        LocalizedStringResource("auth.login.password", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Button to switch to Quick Connect authentication
     
     Localized string for key “auth.login.quickConnect” in table “Localizable.xcstrings”.
     */
    static var authLoginQuickConnect: LocalizedStringResource {
        LocalizedStringResource("auth.login.quickConnect", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Sign in button label
     
     Localized string for key “auth.login.signIn” in table “Localizable.xcstrings”.
     */
    static var authLoginSignIn: LocalizedStringResource {
        LocalizedStringResource("auth.login.signIn", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Subtitle on the login screen
     
     Localized string for key “auth.login.subtitle” in table “Localizable.xcstrings”.
     */
    static var authLoginSubtitle: LocalizedStringResource {
        LocalizedStringResource("auth.login.subtitle", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Placeholder for the username field
     
     Localized string for key “auth.login.username” in table “Localizable.xcstrings”.
     */
    static var authLoginUsername: LocalizedStringResource {
        LocalizedStringResource("auth.login.username", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Welcome message shown after successful login with username
     
     Localized string for key “auth.login.welcome %@” in table “Localizable.xcstrings”.
     */
    static func authLoginWelcome(_ arg1: String) -> LocalizedStringResource {
        LocalizedStringResource("auth.login.welcome %@", defaultValue: "\(arg1)", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Button to complete Quick Connect authentication after code is authorized
     
     Localized string for key “auth.quickConnect.authenticate” in table “Localizable.xcstrings”.
     */
    static var authQuickConnectAuthenticate: LocalizedStringResource {
        LocalizedStringResource("auth.quickConnect.authenticate", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Button to cancel Quick Connect and return to login form
     
     Localized string for key “auth.quickConnect.cancel” in table “Localizable.xcstrings”.
     */
    static var authQuickConnectCancel: LocalizedStringResource {
        LocalizedStringResource("auth.quickConnect.cancel", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Instruction text for Quick Connect code
     
     Localized string for key “auth.quickConnect.instruction” in table “Localizable.xcstrings”.
     */
    static var authQuickConnectInstruction: LocalizedStringResource {
        LocalizedStringResource("auth.quickConnect.instruction", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Title for the Quick Connect section
     
     Localized string for key “auth.quickConnect.title” in table “Localizable.xcstrings”.
     */
    static var authQuickConnectTitle: LocalizedStringResource {
        LocalizedStringResource("auth.quickConnect.title", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Text shown while waiting for Quick Connect authorization
     
     Localized string for key “auth.quickConnect.waiting” in table “Localizable.xcstrings”.
     */
    static var authQuickConnectWaiting: LocalizedStringResource {
        LocalizedStringResource("auth.quickConnect.waiting", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Button to connect to the entered server
     
     Localized string for key “auth.server.connect” in table “Localizable.xcstrings”.
     */
    static var authServerConnect: LocalizedStringResource {
        LocalizedStringResource("auth.server.connect", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Placeholder text in the server address text field
     
     Localized string for key “auth.server.placeholder” in table “Localizable.xcstrings”.
     */
    static var authServerPlaceholder: LocalizedStringResource {
        LocalizedStringResource("auth.server.placeholder", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Subtitle on the server discovery screen explaining what to enter
     
     Localized string for key “auth.server.subtitle” in table “Localizable.xcstrings”.
     */
    static var authServerSubtitle: LocalizedStringResource {
        LocalizedStringResource("auth.server.subtitle", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Title on the server discovery screen
     
     Localized string for key “auth.server.title” in table “Localizable.xcstrings”.
     */
    static var authServerTitle: LocalizedStringResource {
        LocalizedStringResource("auth.server.title", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Cast section
     
     Localized string for key “detail.cast” in table “Localizable.xcstrings”.
     */
    static var detailCast: LocalizedStringResource {
        LocalizedStringResource("detail.cast", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Number of items in collection
     
     Localized string for key “detail.collection.itemCount %lld” in table “Localizable.xcstrings”.
     */
    static func detailCollectionItemCount(_ arg1: Int) -> LocalizedStringResource {
        LocalizedStringResource("detail.collection.itemCount %lld", defaultValue: "\(arg1, specifier: "%lld")", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Collection items section title
     
     Localized string for key “detail.collection.items” in table “Localizable.xcstrings”.
     */
    static var detailCollectionItems: LocalizedStringResource {
        LocalizedStringResource("detail.collection.items", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Context menu: show episode details
     
     Localized string for key “detail.episode.showDetails” in table “Localizable.xcstrings”.
     */
    static var detailEpisodeShowDetails: LocalizedStringResource {
        LocalizedStringResource("detail.episode.showDetails", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Favorite button
     
     Localized string for key “detail.favorite” in table “Localizable.xcstrings”.
     */
    static var detailFavorite: LocalizedStringResource {
        LocalizedStringResource("detail.favorite", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Play button
     
     Localized string for key “detail.play” in table “Localizable.xcstrings”.
     */
    static var detailPlay: LocalizedStringResource {
        LocalizedStringResource("detail.play", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Replay from start button
     
     Localized string for key “detail.replay” in table “Localizable.xcstrings”.
     */
    static var detailReplay: LocalizedStringResource {
        LocalizedStringResource("detail.replay", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Resume button
     
     Localized string for key “detail.resume” in table “Localizable.xcstrings”.
     */
    static var detailResume: LocalizedStringResource {
        LocalizedStringResource("detail.resume", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Number of seasons
     
     Localized string for key “detail.seasonCount %lld” in table “Localizable.xcstrings”.
     */
    static func detailSeasonCount(_ arg1: Int) -> LocalizedStringResource {
        LocalizedStringResource("detail.seasonCount %lld", defaultValue: "\(arg1, specifier: "%lld")", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Deselect episode
     
     Localized string for key “detail.showSeries” in table “Localizable.xcstrings”.
     */
    static var detailShowSeries: LocalizedStringResource {
        LocalizedStringResource("detail.showSeries", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for similar items
     
     Localized string for key “detail.similar” in table “Localizable.xcstrings”.
     */
    static var detailSimilar: LocalizedStringResource {
        LocalizedStringResource("detail.similar", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.audio” in table “Localizable.xcstrings”.
     */
    static var detailTechAudio: LocalizedStringResource {
        LocalizedStringResource("detail.tech.audio", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.bitrate” in table “Localizable.xcstrings”.
     */
    static var detailTechBitrate: LocalizedStringResource {
        LocalizedStringResource("detail.tech.bitrate", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.channels” in table “Localizable.xcstrings”.
     */
    static var detailTechChannels: LocalizedStringResource {
        LocalizedStringResource("detail.tech.channels", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.codec” in table “Localizable.xcstrings”.
     */
    static var detailTechCodec: LocalizedStringResource {
        LocalizedStringResource("detail.tech.codec", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.file” in table “Localizable.xcstrings”.
     */
    static var detailTechFile: LocalizedStringResource {
        LocalizedStringResource("detail.tech.file", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.filename” in table “Localizable.xcstrings”.
     */
    static var detailTechFilename: LocalizedStringResource {
        LocalizedStringResource("detail.tech.filename", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.format” in table “Localizable.xcstrings”.
     */
    static var detailTechFormat: LocalizedStringResource {
        LocalizedStringResource("detail.tech.format", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.framerate” in table “Localizable.xcstrings”.
     */
    static var detailTechFramerate: LocalizedStringResource {
        LocalizedStringResource("detail.tech.framerate", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.hdr” in table “Localizable.xcstrings”.
     */
    static var detailTechHdr: LocalizedStringResource {
        LocalizedStringResource("detail.tech.hdr", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.language” in table “Localizable.xcstrings”.
     */
    static var detailTechLanguage: LocalizedStringResource {
        LocalizedStringResource("detail.tech.language", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.resolution” in table “Localizable.xcstrings”.
     */
    static var detailTechResolution: LocalizedStringResource {
        LocalizedStringResource("detail.tech.resolution", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.size” in table “Localizable.xcstrings”.
     */
    static var detailTechSize: LocalizedStringResource {
        LocalizedStringResource("detail.tech.size", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.subtitles” in table “Localizable.xcstrings”.
     */
    static var detailTechSubtitles: LocalizedStringResource {
        LocalizedStringResource("detail.tech.subtitles", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.tracks” in table “Localizable.xcstrings”.
     */
    static var detailTechTracks: LocalizedStringResource {
        LocalizedStringResource("detail.tech.tracks", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     
     
     Localized string for key “detail.tech.video” in table “Localizable.xcstrings”.
     */
    static var detailTechVideo: LocalizedStringResource {
        LocalizedStringResource("detail.tech.video", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Tech info section
     
     Localized string for key “detail.techInfo” in table “Localizable.xcstrings”.
     */
    static var detailTechInfo: LocalizedStringResource {
        LocalizedStringResource("detail.techInfo", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Unfavorite button
     
     Localized string for key “detail.unfavorite” in table “Localizable.xcstrings”.
     */
    static var detailUnfavorite: LocalizedStringResource {
        LocalizedStringResource("detail.unfavorite", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Error when response cannot be decoded
     
     Localized string for key “error.decodingError” in table “Localizable.xcstrings”.
     */
    static var errorDecodingError: LocalizedStringResource {
        LocalizedStringResource("error.decodingError", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Error with HTTP status code
     
     Localized string for key “error.httpError %lld” in table “Localizable.xcstrings”.
     */
    static func errorHttpError(_ arg1: Int) -> LocalizedStringResource {
        LocalizedStringResource("error.httpError %lld", defaultValue: "\(arg1, specifier: "%lld")", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Error when server response is invalid
     
     Localized string for key “error.invalidResponse” in table “Localizable.xcstrings”.
     */
    static var errorInvalidResponse: LocalizedStringResource {
        LocalizedStringResource("error.invalidResponse", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Error when URL is invalid
     
     Localized string for key “error.invalidURL” in table “Localizable.xcstrings”.
     */
    static var errorInvalidURL: LocalizedStringResource {
        LocalizedStringResource("error.invalidURL", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Error when network connection fails
     
     Localized string for key “error.networkError” in table “Localizable.xcstrings”.
     */
    static var errorNetworkError: LocalizedStringResource {
        LocalizedStringResource("error.networkError", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Error when server cannot be reached
     
     Localized string for key “error.serverUnreachable” in table “Localizable.xcstrings”.
     */
    static var errorServerUnreachable: LocalizedStringResource {
        LocalizedStringResource("error.serverUnreachable", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Error when request times out
     
     Localized string for key “error.timeout” in table “Localizable.xcstrings”.
     */
    static var errorTimeout: LocalizedStringResource {
        LocalizedStringResource("error.timeout", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Error when authentication is required
     
     Localized string for key “error.unauthorized” in table “Localizable.xcstrings”.
     */
    static var errorUnauthorized: LocalizedStringResource {
        LocalizedStringResource("error.unauthorized", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for all movies
     
     Localized string for key “home.allMovies” in table “Localizable.xcstrings”.
     */
    static var homeAllMovies: LocalizedStringResource {
        LocalizedStringResource("home.allMovies", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for all series
     
     Localized string for key “home.allSeries” in table “Localizable.xcstrings”.
     */
    static var homeAllSeries: LocalizedStringResource {
        LocalizedStringResource("home.allSeries", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for collections
     
     Localized string for key “home.collections” in table “Localizable.xcstrings”.
     */
    static var homeCollections: LocalizedStringResource {
        LocalizedStringResource("home.collections", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for continue watching row
     
     Localized string for key “home.continueWatching” in table “Localizable.xcstrings”.
     */
    static var homeContinueWatching: LocalizedStringResource {
        LocalizedStringResource("home.continueWatching", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section header for active rows
     
     Localized string for key “home.customize.active” in table “Localizable.xcstrings”.
     */
    static var homeCustomizeActive: LocalizedStringResource {
        LocalizedStringResource("home.customize.active", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Description in home customize view
     
     Localized string for key “home.customize.description” in table “Localizable.xcstrings”.
     */
    static var homeCustomizeDescription: LocalizedStringResource {
        LocalizedStringResource("home.customize.description", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section header for inactive rows
     
     Localized string for key “home.customize.inactive” in table “Localizable.xcstrings”.
     */
    static var homeCustomizeInactive: LocalizedStringResource {
        LocalizedStringResource("home.customize.inactive", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Tip when a row is selected for moving
     
     Localized string for key “home.customize.moveTip” in table “Localizable.xcstrings”.
     */
    static var homeCustomizeMoveTip: LocalizedStringResource {
        LocalizedStringResource("home.customize.moveTip", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Label shown on row being moved
     
     Localized string for key “home.customize.moving” in table “Localizable.xcstrings”.
     */
    static var homeCustomizeMoving: LocalizedStringResource {
        LocalizedStringResource("home.customize.moving", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Button to restore default home layout
     
     Localized string for key “home.customize.resetDefaults” in table “Localizable.xcstrings”.
     */
    static var homeCustomizeResetDefaults: LocalizedStringResource {
        LocalizedStringResource("home.customize.resetDefaults", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Title for home customization
     
     Localized string for key “home.customize.title” in table “Localizable.xcstrings”.
     */
    static var homeCustomizeTitle: LocalizedStringResource {
        LocalizedStringResource("home.customize.title", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for favorites
     
     Localized string for key “home.favorites” in table “Localizable.xcstrings”.
     */
    static var homeFavorites: LocalizedStringResource {
        LocalizedStringResource("home.favorites", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for genres
     
     Localized string for key “home.genres” in table “Localizable.xcstrings”.
     */
    static var homeGenres: LocalizedStringResource {
        LocalizedStringResource("home.genres", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for latest movies
     
     Localized string for key “home.latestMovies” in table “Localizable.xcstrings”.
     */
    static var homeLatestMovies: LocalizedStringResource {
        LocalizedStringResource("home.latestMovies", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for latest TV shows
     
     Localized string for key “home.latestShows” in table “Localizable.xcstrings”.
     */
    static var homeLatestShows: LocalizedStringResource {
        LocalizedStringResource("home.latestShows", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for next up episodes
     
     Localized string for key “home.nextUp” in table “Localizable.xcstrings”.
     */
    static var homeNextUp: LocalizedStringResource {
        LocalizedStringResource("home.nextUp", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for recently added
     
     Localized string for key “home.recentlyAdded” in table “Localizable.xcstrings”.
     */
    static var homeRecentlyAdded: LocalizedStringResource {
        LocalizedStringResource("home.recentlyAdded", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for studios/providers
     
     Localized string for key “home.studios” in table “Localizable.xcstrings”.
     */
    static var homeStudios: LocalizedStringResource {
        LocalizedStringResource("home.studios", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for top rated movies
     
     Localized string for key “home.topRatedMovies” in table “Localizable.xcstrings”.
     */
    static var homeTopRatedMovies: LocalizedStringResource {
        LocalizedStringResource("home.topRatedMovies", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Section title for top rated shows
     
     Localized string for key “home.topRatedShows” in table “Localizable.xcstrings”.
     */
    static var homeTopRatedShows: LocalizedStringResource {
        LocalizedStringResource("home.topRatedShows", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Server address label
     
     Localized string for key “settings.about.serverAddress” in table “Localizable.xcstrings”.
     */
    static var settingsAboutServerAddress: LocalizedStringResource {
        LocalizedStringResource("settings.about.serverAddress", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Server version label
     
     Localized string for key “settings.about.serverVersion” in table “Localizable.xcstrings”.
     */
    static var settingsAboutServerVersion: LocalizedStringResource {
        LocalizedStringResource("settings.about.serverVersion", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     App version label
     
     Localized string for key “settings.about.version” in table “Localizable.xcstrings”.
     */
    static var settingsAboutVersion: LocalizedStringResource {
        LocalizedStringResource("settings.about.version", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Navigate to home customization
     
     Localized string for key “settings.home.customize” in table “Localizable.xcstrings”.
     */
    static var settingsHomeCustomize: LocalizedStringResource {
        LocalizedStringResource("settings.home.customize", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Subtitle for home customize tile
     
     Localized string for key “settings.home.customizeSubtitle” in table “Localizable.xcstrings”.
     */
    static var settingsHomeCustomizeSubtitle: LocalizedStringResource {
        LocalizedStringResource("settings.home.customizeSubtitle", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Logout button in settings
     
     Localized string for key “settings.logout” in table “Localizable.xcstrings”.
     */
    static var settingsLogout: LocalizedStringResource {
        LocalizedStringResource("settings.logout", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Placeholder for playback settings
     
     Localized string for key “settings.playback.comingSoon” in table “Localizable.xcstrings”.
     */
    static var settingsPlaybackComingSoon: LocalizedStringResource {
        LocalizedStringResource("settings.playback.comingSoon", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Subtitle for playback settings tile
     
     Localized string for key “settings.playback.subtitle” in table “Localizable.xcstrings”.
     */
    static var settingsPlaybackSubtitle: LocalizedStringResource {
        LocalizedStringResource("settings.playback.subtitle", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Playback settings navigation label
     
     Localized string for key “settings.playback.title” in table “Localizable.xcstrings”.
     */
    static var settingsPlaybackTitle: LocalizedStringResource {
        LocalizedStringResource("settings.playback.title", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Tab label for the Seerr catalog/discovery screen
     
     Localized string for key “tab.catalog” in table “Localizable.xcstrings”.
     */
    static var tabCatalog: LocalizedStringResource {
        LocalizedStringResource("tab.catalog", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Tab label for the home screen
     
     Localized string for key “tab.home” in table “Localizable.xcstrings”.
     */
    static var tabHome: LocalizedStringResource {
        LocalizedStringResource("tab.home", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Tab label for the search screen
     
     Localized string for key “tab.search” in table “Localizable.xcstrings”.
     */
    static var tabSearch: LocalizedStringResource {
        LocalizedStringResource("tab.search", table: "Localizable", bundle: resourceBundleDescription)
    }

    /**
     Tab label for the settings screen
     
     Localized string for key “tab.settings” in table “Localizable.xcstrings”.
     */
    static var tabSettings: LocalizedStringResource {
        LocalizedStringResource("tab.settings", table: "Localizable", bundle: resourceBundleDescription)
    }
}