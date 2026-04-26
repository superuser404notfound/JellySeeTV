import SwiftUI

@main
struct JellySeeTVApp: App {
    @State private var appState = AppState()
    @State private var dependencies = DependencyContainer()

    init() {
        // FIRST thing the app does — before any other UserDefaults
        // reader/writer touches CFPreferences. Earlier builds wrote
        // the home + catalog filter caches into UserDefaults, which
        // tvOS caps at 1 MB per app domain. Once that ceiling is hit
        // any subsequent `defaults.set(...)` (even unrelated tiny
        // writes from other features) crashes the app with SIGABRT,
        // because CFPreferences re-flushes the *entire* plist on
        // every change.
        //
        // A `removeObject` sweep alone isn't enough on devices that
        // already have the broken plist on disk — the file itself
        // can be corrupt (the system has even logged
        // `<decode: bad range>` errors), so subsequent flushes still
        // overwrite a malformed blob. The only reliable recovery is
        // `removePersistentDomain`, which deletes the underlying
        // file and lets a fresh one get written. We snapshot the
        // small legitimate keys first and restore them afterwards
        // so the user keeps their home customisation, default
        // profile, accent colour, etc.
        Self.recoverBloatedDefaultsIfNeeded()
    }

    /// Per-bundle marker recording whether the one-shot recovery has
    /// already completed for this install. Lives in `Library/Caches`
    /// so it survives the UserDefaults wipe but disappears with the
    /// app, exactly the lifetime we want.
    private static let recoveryMarkerName = "userDefaultsRecovered.v1"

    private static func recoverBloatedDefaultsIfNeeded() {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        let marker = caches?.appendingPathComponent(recoveryMarkerName)
        if let marker, fm.fileExists(atPath: marker.path) { return }

        let defaults = UserDefaults.standard
        let bundleID = Bundle.main.bundleIdentifier ?? "de.superuser404.JellySeeTV"

        // Snapshot every key that *isn't* part of the legacy
        // FilterCache mess and that's small enough we know it can't
        // be a hidden bloat source. A 64 KB ceiling is comfortably
        // above any real preference we ship (the largest is the home
        // row config blob at <1 KB) but well below the 1 MB plist
        // cap, so even if dictionaryRepresentation hands us a stale
        // value from a corrupt plist, we won't re-introduce it.
        var snapshot: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() {
            if key.hasPrefix("FilterCache.") { continue }
            if estimatedSize(of: value) > 64_000 { continue }
            snapshot[key] = value
        }

        // Wipe the entire domain — deletes the underlying plist,
        // including any corruption.
        defaults.removePersistentDomain(forName: bundleID)

        // Restore the snapshot. Each `set` writes a fresh tiny plist;
        // none of these values are large, so the cumulative flush
        // stays orders of magnitude below the cap.
        for (key, value) in snapshot {
            defaults.set(value, forKey: key)
        }

        if let marker {
            try? fm.createDirectory(
                at: marker.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? Data().write(to: marker)
        }
    }

    /// Best-effort byte estimate. We only care about catching obvious
    /// bloat (Data/String values that grew unbounded), not exact
    /// accounting — anything we can't measure cheaply we treat as
    /// small and let through.
    private static func estimatedSize(of value: Any) -> Int {
        switch value {
        case let data as Data: return data.count
        case let string as String: return string.utf8.count
        case let array as [Any]:
            return array.reduce(0) { $0 + estimatedSize(of: $1) }
        case let dict as [String: Any]:
            return dict.reduce(0) { $0 + $1.key.utf8.count + estimatedSize(of: $1.value) }
        default:
            return 8
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environment(\.appState, appState)
                .environment(\.dependencies, dependencies)
                .preferredColorScheme(.dark)
                .tint(dependencies.appearancePreferences.effectiveTint(
                    isSupporter: dependencies.storeKitService.isSupporter
                ))
        }
    }
}
