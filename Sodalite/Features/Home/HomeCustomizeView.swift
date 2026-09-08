import SwiftUI

struct HomeCustomizeView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var configs: [HomeRowConfig] = []
    @State private var movingID: String?
    @State private var mergeCWNextUp = false
    @State private var rewatchNextUp = false
    @State private var collectionGrouping: CollectionGrouping = .system

    private var serverID: String {
        appState.activeServer?.id ?? appState.activeUser?.id ?? ""
    }

    /// tvOS 10-foot row inset; iPhone compact needs phone scale or the row content overflows.
    private var hInset: CGFloat { hSizeClass == .compact ? 16 : 50 }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                mergeRowToggle
                rewatchRowToggle
                collectionGroupingRow
                rowList
            }
            .padding(.vertical, 40)
        }
        .hidesNavigationBarChrome()
        .hidesShellTabBar()
        .onAppear {
            configs = HomeRowConfig.loadFromStorage(serverID: serverID)
            mergeCWNextUp = HomeRowConfig.mergeContinueWatchingNextUp(serverID: serverID)
            rewatchNextUp = HomeRowConfig.enableRewatchingNextUp(serverID: serverID)
            collectionGrouping = HomeRowConfig.collectionGrouping(serverID: serverID)
            // Per-library rows are otherwise discovered only on Home load, so Customize showed a stale list right after a server add/switch. Reconcile here too.
            Task { await reconcileLibraries() }
        }
    }

    /// Fold new per-library rows into the config, mirroring HomeViewModel. Additive (keeps toggles/order); persists only on success so a transient failure can't wipe the dynamic rows.
    private func reconcileLibraries() async {
        guard let userID = appState.activeUser?.id,
              let libraries = try? await dependencies.jellyfinLibraryService.getLibraries(userID: userID)
        else { return }
        let reconciled = HomeRowConfig.reconciled(stored: configs, libraries: libraries)
        if reconciled != configs {
            configs = reconciled
            HomeRowConfig.saveToStorage(reconciled, serverID: serverID)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("home.customize.title")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(movingID != nil ? "home.customize.moveTip" : "home.customize.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            FocusableTile(action: {
                movingID = nil
                withAnimation(.easeInOut(duration: 0.25)) {
                    configs = HomeRowConfig.resetToDefault(current: configs)
                }
                save()
            }) { isFocused in
                Label("home.customize.resetDefaults", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(isFocused ? Color.Theme.focusFill : .white.opacity(0.05))
                    )
            }
        }
        .padding(.horizontal, hInset)
    }

    // MARK: - Merge toggle

    /// Combined row toggle: folds Next Up into Continue Watching. Here not Appearance because it changes which rows exist. ValuePickerRow (left/right), not a tap-toggle, per app convention.
    private var mergeRowToggle: some View {
        ValuePickerRow(
            icon: "arrow.triangle.merge",
            title: "home.customize.mergeCwNextUp",
            subtitle: "home.customize.mergeCwNextUp.subtitle",
            options: [false, true],
            selection: Binding(
                get: { mergeCWNextUp },
                set: { newValue in
                    movingID = nil
                    withAnimation(.easeInOut(duration: 0.25)) {
                        mergeCWNextUp = newValue
                    }
                    HomeRowConfig.setMergeContinueWatchingNextUp(newValue, serverID: serverID)
                    NotificationCenter.default.post(name: .homeConfigDidChange, object: nil)
                }
            ),
            label: { on in
                on
                    ? String(localized: "common.on", defaultValue: "On")
                    : String(localized: "common.off", defaultValue: "Off")
            }
        )
        .padding(.horizontal, hInset)
    }

    // MARK: - Rewatching toggle

    /// Jellyfin EnableRewatching for Next Up: keeps surfacing the next episode after a series is fully watched. ValuePickerRow per server, drives a Home reload via .homeConfigDidChange.
    private var rewatchRowToggle: some View {
        ValuePickerRow(
            icon: "arrow.clockwise",
            title: "home.customize.rewatchNextUp",
            subtitle: "home.customize.rewatchNextUp.subtitle",
            options: [false, true],
            selection: Binding(
                get: { rewatchNextUp },
                set: { newValue in
                    movingID = nil
                    rewatchNextUp = newValue
                    HomeRowConfig.setEnableRewatchingNextUp(newValue, serverID: serverID)
                    NotificationCenter.default.post(name: .homeConfigDidChange, object: nil)
                }
            ),
            label: { on in
                on
                    ? String(localized: "common.on", defaultValue: "On")
                    : String(localized: "common.off", defaultValue: "Off")
            }
        )
        .padding(.horizontal, hInset)
    }

    // MARK: - Collection grouping

    /// Jellyfin's server-wide "Group movies into collections" for the My Media grids (Sodalite#44). Server default sends no CollapseBoxSetItems at all, which is the only way the server option applies; the other two override it on this device.
    private var collectionGroupingRow: some View {
        ValuePickerRow(
            icon: "rectangle.stack",
            title: "home.customize.collectionGrouping",
            subtitle: "home.customize.collectionGrouping.subtitle",
            options: CollectionGrouping.allCases,
            selection: Binding(
                get: { collectionGrouping },
                set: { newValue in
                    movingID = nil
                    collectionGrouping = newValue
                    HomeRowConfig.setCollectionGrouping(newValue, serverID: serverID)
                    // The grids cache per mode, so no stale shape survives; Home still reloads for the My Media tiles.
                    NotificationCenter.default.post(name: .homeConfigDidChange, object: nil)
                }
            ),
            label: { $0.localizedLabel }
        )
        .padding(.horizontal, hInset)
    }

    // MARK: - Row list

    /// Unified ordered list; disabled rows sink below a divider. Two focus targets per row (body reorders/re-enables, trailing switch shows/hides) so each stays a plain clickpad press the Siri Remote delivers reliably; one element with a directional toggle made the reorder click ambiguous and swallowed it.
    private var rowList: some View {
        VStack(spacing: 6) {
            ForEach(Array(enabledRows.enumerated()), id: \.element.id) { index, config in
                enabledRow(config, at: index)
            }

            if !disabledRows.isEmpty {
                inactiveDivider
                ForEach(disabledRows) { config in
                    disabledRow(config)
                }
            }
        }
    }

    /// Thin "Inactive" separator so the two groups read as one list.
    private var inactiveDivider: some View {
        HStack(spacing: 12) {
            Text("home.customize.inactive")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
        }
        .padding(.horizontal, hInset)
        .padding(.top, 18)
        .padding(.bottom, 2)
    }

    // MARK: - Enabled row

    private func enabledRow(_ config: HomeRowConfig, at index: Int) -> some View {
        HStack(spacing: 16) {
            FocusableTile(
                isHighlighted: movingID == config.id,
                action: { handleRowTap(config.id, at: index) }
            ) { isFocused in
                rowBody(config, isFocused: isFocused, isEnabled: true)
            }

            RowToggleButton(isOn: true) {
                movingID = nil
                toggle(id: config.id)
            }
        }
        .padding(.horizontal, hInset)
    }

    // MARK: - Disabled row

    /// Disabled rows have no Home position, so the body click also re-activates the row (forgiving target).
    private func disabledRow(_ config: HomeRowConfig) -> some View {
        HStack(spacing: 16) {
            FocusableTile(action: { toggle(id: config.id) }) { isFocused in
                rowBody(config, isFocused: isFocused, isEnabled: false)
            }

            RowToggleButton(isOn: false) {
                toggle(id: config.id)
            }
        }
        .padding(.horizontal, hInset)
    }

    /// Shared left side of a row: icon, label and the "moving" indicator.
    @ViewBuilder
    private func rowBody(_ config: HomeRowConfig, isFocused: Bool, isEnabled: Bool) -> some View {
        HStack(spacing: 20) {
            Image(systemName: config.systemImage)
                .font(.title3)
                .frame(width: 44)
                .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

            rowLabel(config)
                .font(.body)
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

            Spacer()

            if movingID == config.id {
                Text("home.customize.moving")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tileBackground(isFocused: isFocused, isMoving: movingID == config.id, isEnabled: isEnabled))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(movingID == config.id ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(Color.clear), lineWidth: 2)
        )
        .overlay(
            // Accent focus stroke (app-wide 3pt); when focused + picked up, this opaque stroke dominates the thinner move ring.
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.tint, lineWidth: 3)
                .opacity(isFocused ? 1 : 0)
        )
    }

    // MARK: - Helpers

    private func tileBackground(isFocused: Bool, isMoving: Bool, isEnabled: Bool) -> AnyShapeStyle {
        if isMoving { return AnyShapeStyle(TintShapeStyle.tint.opacity(0.12)) }
        if isFocused { return AnyShapeStyle(Color.Theme.focusFill) }
        return AnyShapeStyle(isEnabled ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
    }

    /// Up Next drops from both lists while merge is on (it rides inside Continue Watching then; an orderable-but-inert row would confuse).
    private var enabledRows: [HomeRowConfig] {
        configs
            .filter(\.isEnabled)
            .filter { !(mergeCWNextUp && $0.type == .nextUp) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var disabledRows: [HomeRowConfig] {
        configs.filter { !$0.isEnabled && !(mergeCWNextUp && $0.type == .nextUp) }
    }

    @ViewBuilder
    private func rowLabel(_ config: HomeRowConfig) -> some View {
        if config.type == .libraryLatest {
            Text(
                String(
                    format: String(localized: "home.libraryLatest.format", defaultValue: "Latest in %@"),
                    config.libraryName ?? ""
                )
            )
        } else {
            Text(config.type.localizedTitle)
        }
    }

    // MARK: - Actions

    private func handleRowTap(_ id: String, at index: Int) {
        if let moving = movingID {
            if moving != id {
                withAnimation(.easeInOut(duration: 0.25)) {
                    placeRow(id: moving, at: index)
                }
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                movingID = nil
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                movingID = id
            }
        }
    }

    private func placeRow(id: String, at targetIndex: Int) {
        var enabled = enabledRows
        guard let sourceIndex = enabled.firstIndex(where: { $0.id == id }) else { return }
        let item = enabled.remove(at: sourceIndex)
        enabled.insert(item, at: min(targetIndex, enabled.count))
        for (i, row) in enabled.enumerated() {
            if let ci = configs.firstIndex(where: { $0.id == row.id }) {
                configs[ci].sortOrder = i
            }
        }
        save()
    }

    private func toggle(id: String) {
        guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            configs[index].isEnabled.toggle()
            if configs[index].isEnabled {
                let maxOrder = configs.filter(\.isEnabled).map(\.sortOrder).max() ?? 0
                configs[index].sortOrder = maxOrder + 1
            }
        }
        save()
    }

    private func save() {
        HomeRowConfig.saveToStorage(configs, serverID: serverID)
        NotificationCenter.default.post(name: .homeConfigDidChange, object: nil)
    }
}

// MARK: - Focusable Tile (no default tvOS button chrome)

struct FocusableTile<Content: View>: View {
    var isHighlighted: Bool = false
    let action: () -> Void
    @ViewBuilder let content: (_ isFocused: Bool) -> Content

    @FocusState private var isFocused: Bool

    var body: some View {
        content(isFocused)
            .focusable()
            .focused($isFocused)
            .focusResponse(.inline, isFocused: isFocused)
            .stableTap(isFocused: isFocused) { action() }
    }
}

// MARK: - Row On/Off switch (show / hide a row on Home)

/// Trailing show/hide control. Own focus target, single clickpad gesture, so it never competes with the row body's reorder click; a directional toggle here would trap focus against the body beside it.
struct RowToggleButton: View {
    let isOn: Bool
    let action: () -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @FocusState private var focused: Bool

    private var isCompact: Bool { hSizeClass == .compact }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOn ? "eye.fill" : "eye.slash")
                .font(.body)
            Text(isOn
                ? String(localized: "common.on", defaultValue: "On")
                : String(localized: "common.off", defaultValue: "Off"))
                .font(.body)
                .fontWeight(.semibold)
                .contentTransition(.opacity)
        }
        .foregroundStyle(foreground)
        .frame(minWidth: isCompact ? 64 : 104)
        .padding(.horizontal, isCompact ? 12 : 18)
        .padding(.vertical, 12)
        .background(
            Capsule().fill(background)
        )
        .overlay(
            Capsule()
                .strokeBorder(.tint, lineWidth: 3)
                .opacity(focused ? 1 : 0)
        )
        .focusResponse(.chip, isFocused: focused)
        .animation(.easeInOut(duration: 0.15), value: isOn)
        .focusable()
        .focused($focused)
        .stableTap(isFocused: focused) { action() }
    }

    private var foreground: AnyShapeStyle {
        if isOn { return focused ? AnyShapeStyle(.white) : AnyShapeStyle(.tint) }
        return focused ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary)
    }

    private var background: AnyShapeStyle {
        if isOn { return AnyShapeStyle(TintShapeStyle.tint.opacity(focused ? 0.4 : 0.2)) }
        return AnyShapeStyle(Color.white.opacity(focused ? 0.18 : 0.06))
    }
}

// MARK: - Storage

extension HomeRowConfig {
    private static let legacyKey = "homeRowConfigs"
    private static func storageKey(serverID: String) -> String {
        "homeRowConfigs.\(serverID)"
    }

    static func loadFromStorage(serverID: String) -> [HomeRowConfig] {
        let key = storageKey(serverID: serverID)
        // Migrate a pre-multi-server install: adopt the legacy global config if this server has no scoped one yet.
        let data = UserDefaults.standard.data(forKey: key)
            ?? UserDefaults.standard.data(forKey: legacyKey)
        guard let data else {
            return HomeRowConfig.defaultConfig()
        }
        // Lossy decode via JSONSerialization: stored configs may reference retired row types, and a plain decode fails the whole array on the first unknown raw value, silently resetting every customization.
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return HomeRowConfig.defaultConfig()
        }
        var result: [HomeRowConfig] = []
        for item in raw {
            guard let typeRaw = item["type"] as? String,
                  let type = HomeRowType(rawValue: typeRaw),
                  let isEnabled = item["isEnabled"] as? Bool,
                  let sortOrder = item["sortOrder"] as? Int
            else { continue }
            // libraryLatest rows require a libraryID; skip malformed ones.
            let libraryID = item["libraryID"] as? String
            if type == .libraryLatest, libraryID == nil { continue }
            result.append(
                HomeRowConfig(
                    type: type,
                    isEnabled: isEnabled,
                    sortOrder: sortOrder,
                    libraryID: libraryID,
                    libraryName: item["libraryName"] as? String,
                    collectionType: item["collectionType"] as? String
                )
            )
        }
        // Backfill newly-added static row types (never libraryLatest).
        for type in HomeRowType.allCases where type != .libraryLatest
            && !result.contains(where: { $0.type == type }) {
            result.append(HomeRowConfig(type: type, isEnabled: type.defaultEnabled, sortOrder: result.count))
        }
        return result
    }

    static func saveToStorage(_ configs: [HomeRowConfig], serverID: String) {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(serverID: serverID))
    }

    /// Raw stored JSON for cloud sync; kept opaque so the lossy-decode
    /// forward compatibility in loadFromStorage is preserved end to end.
    static func rawConfigData(serverID: String) -> Data? {
        UserDefaults.standard.data(forKey: storageKey(serverID: serverID))
    }

    static func setRawConfigData(_ data: Data, serverID: String) {
        UserDefaults.standard.set(data, forKey: storageKey(serverID: serverID))
    }

    // MARK: Merge Continue Watching + Up Next

    private static func mergeKey(serverID: String) -> String {
        "homeMergeCWNextUp.\(serverID)"
    }

    /// Combined row (Sodalite#15): when on, Continue Watching carries Next Up (resume first) and the separate Up Next row drops. Per server, default off.
    static func mergeContinueWatchingNextUp(serverID: String) -> Bool {
        UserDefaults.standard.bool(forKey: mergeKey(serverID: serverID))
    }

    static func setMergeContinueWatchingNextUp(_ value: Bool, serverID: String) {
        UserDefaults.standard.set(value, forKey: mergeKey(serverID: serverID))
    }

    // MARK: Enable Rewatching in Next Up

    private static func rewatchingKey(serverID: String) -> String {
        "homeRewatchNextUp.\(serverID)"
    }

    /// EnableRewatching for /Shows/NextUp (Sodalite#19): keeps surfacing the next episode after a series is fully watched. Home Next Up row (standalone + merged path). Per server, default off.
    static func enableRewatchingNextUp(serverID: String) -> Bool {
        UserDefaults.standard.bool(forKey: rewatchingKey(serverID: serverID))
    }

    static func setEnableRewatchingNextUp(_ value: Bool, serverID: String) {
        UserDefaults.standard.set(value, forKey: rewatchingKey(serverID: serverID))
    }

    // MARK: Collection grouping in the library grids

    private static func collectionGroupingKey(serverID: String) -> String {
        "libraryCollectionGrouping.\(serverID)"
    }

    /// Whether the My Media grids fold a BoxSet's movies into one collection tile (Sodalite#44). Per server, mirroring the server-wide Jellyfin option it defers to; default `.system` (follow the server).
    static func collectionGrouping(serverID: String) -> CollectionGrouping {
        CollectionGrouping(
            storedValue: UserDefaults.standard.string(forKey: collectionGroupingKey(serverID: serverID))
        )
    }

    static func setCollectionGrouping(_ value: CollectionGrouping, serverID: String) {
        UserDefaults.standard.set(value.rawValue, forKey: collectionGroupingKey(serverID: serverID))
    }
}
