import SwiftUI

struct HomeCustomizeView: View {
    @State private var configs: [HomeRowConfig] = HomeRowConfig.loadFromStorage()
    @State private var movingType: HomeRowType?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                activeSection
                if !disabledRows.isEmpty { inactiveSection }
            }
            .padding(.vertical, 40)
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            configs = HomeRowConfig.loadFromStorage()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("home.customize.title")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(movingType != nil ? "home.customize.moveTip" : "home.customize.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            FocusableTile(action: {
                movingType = nil
                withAnimation(.easeInOut(duration: 0.25)) {
                    configs = HomeRowConfig.defaultConfig()
                }
                save()
            }) { isFocused in
                Label("home.customize.resetDefaults", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(isFocused ? .primary : .secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(isFocused ? .white.opacity(0.15) : .white.opacity(0.05))
                    )
            }
        }
        .padding(.horizontal, 50)
    }

    // MARK: - Active

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("home.customize.active", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 50)

            VStack(spacing: 6) {
                ForEach(Array(enabledRows.enumerated()), id: \.element.id) { index, config in
                    HStack(spacing: 16) {
                        FocusableTile(
                            isHighlighted: movingType == config.type,
                            action: { handleRowTap(config.type, at: index) }
                        ) { isFocused in
                            HStack(spacing: 20) {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 24)

                                Image(systemName: config.type.systemImage)
                                    .font(.title3)
                                    .frame(width: 44)
                                    .foregroundStyle(.tint)

                                Text(config.type.localizedTitle)
                                    .font(.body)

                                Spacer()

                                if movingType == config.type {
                                    Text("home.customize.moving")
                                        .font(.caption)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(tileBackground(isFocused: isFocused, isMoving: movingType == config.type))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(movingType == config.type ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 2)
                            )
                        }

                        FocusableIcon(
                            systemName: "minus.circle.fill",
                            color: .red,
                            action: {
                                movingType = nil
                                toggle(config.type)
                            }
                        )
                    }
                    .padding(.horizontal, 50)
                }
            }
        }
    }

    // MARK: - Inactive

    private var inactiveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("home.customize.inactive", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 50)

            VStack(spacing: 6) {
                ForEach(disabledRows) { config in
                    HStack(spacing: 16) {
                        HStack(spacing: 20) {
                            Spacer().frame(width: 24) // align with position number

                            Image(systemName: config.type.systemImage)
                                .font(.title3)
                                .frame(width: 44)
                                .foregroundStyle(.tertiary)

                            Text(config.type.localizedTitle)
                                .font(.body)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.02))
                        )

                        FocusableIcon(
                            systemName: "plus.circle.fill",
                            color: .green,
                            action: { toggle(config.type) }
                        )
                    }
                    .padding(.horizontal, 50)
                }
            }
        }
    }


    // MARK: - Helpers

    private func tileBackground(isFocused: Bool, isMoving: Bool) -> Color {
        if isMoving { return Color.accentColor.opacity(0.12) }
        if isFocused { return .white.opacity(0.12) }
        return .white.opacity(0.05)
    }

    private var enabledRows: [HomeRowConfig] {
        configs.filter(\.isEnabled).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var disabledRows: [HomeRowConfig] {
        configs.filter { !$0.isEnabled }
    }

    // MARK: - Actions

    private func handleRowTap(_ type: HomeRowType, at index: Int) {
        if let moving = movingType {
            if moving != type {
                withAnimation(.easeInOut(duration: 0.25)) {
                    placeRow(moving, at: index)
                }
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                movingType = nil
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                movingType = type
            }
        }
    }

    private func placeRow(_ type: HomeRowType, at targetIndex: Int) {
        var enabled = enabledRows
        guard let sourceIndex = enabled.firstIndex(where: { $0.type == type }) else { return }
        let item = enabled.remove(at: sourceIndex)
        enabled.insert(item, at: min(targetIndex, enabled.count))
        for (i, row) in enabled.enumerated() {
            if let ci = configs.firstIndex(where: { $0.type == row.type }) {
                configs[ci].sortOrder = i
            }
        }
        save()
    }

    private func toggle(_ type: HomeRowType) {
        guard let index = configs.firstIndex(where: { $0.type == type }) else { return }
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
        HomeRowConfig.saveToStorage(configs)
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
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .onLongPressGesture(minimumDuration: 0) {
                action()
            }
    }
}

// MARK: - Focusable Icon Button (plus/minus)

struct FocusableIcon: View {
    let systemName: String
    let color: Color
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Image(systemName: systemName)
            .font(.title2)
            .foregroundStyle(color)
            .frame(width: 60, height: 60)
            .background(
                Circle().fill(isFocused ? .white.opacity(0.15) : .clear)
            )
            .scaleEffect(isFocused ? 1.25 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .focusable()
            .focused($isFocused)
            .onLongPressGesture(minimumDuration: 0) {
                action()
            }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let homeConfigDidChange = Notification.Name("homeConfigDidChange")
    static let homeFavoritesDidChange = Notification.Name("homeFavoritesDidChange")
}

// MARK: - Storage

extension HomeRowConfig {
    static func loadFromStorage() -> [HomeRowConfig] {
        guard let data = UserDefaults.standard.data(forKey: "homeRowConfigs"),
              let configs = try? JSONDecoder().decode([HomeRowConfig].self, from: data)
        else {
            return HomeRowConfig.defaultConfig()
        }
        var result = configs
        for type in HomeRowType.allCases where !result.contains(where: { $0.type == type }) {
            result.append(HomeRowConfig(type: type, isEnabled: type.defaultEnabled, sortOrder: result.count))
        }
        return result
    }

    static func saveToStorage(_ configs: [HomeRowConfig]) {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: "homeRowConfigs")
        UserDefaults.standard.synchronize()
    }
}
