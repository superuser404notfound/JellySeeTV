import SwiftUI

struct HomeCustomizeView: View {
    @State private var configs: [HomeRowConfig] = HomeRowConfig.loadFromStorage()

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("home.customize.title")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("home.customize.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 50)

                // Active rows
                VStack(alignment: .leading, spacing: 12) {
                    Label("home.customize.active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 50)

                    VStack(spacing: 4) {
                        ForEach(Array(enabledRows.enumerated()), id: \.element.id) { index, config in
                            ActiveRowItem(
                                config: config,
                                index: index,
                                isFirst: index == 0,
                                isLast: index == enabledRows.count - 1,
                                onMoveUp: { moveUp(config.type) },
                                onMoveDown: { moveDown(config.type) },
                                onRemove: { toggle(config.type) }
                            )
                        }
                    }
                    .padding(.horizontal, 50)
                }

                // Available rows
                if !disabledRows.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("home.customize.inactive", systemImage: "circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 50)

                        VStack(spacing: 4) {
                            ForEach(disabledRows) { config in
                                InactiveRowItem(config: config) {
                                    toggle(config.type)
                                }
                            }
                        }
                        .padding(.horizontal, 50)
                    }
                }

                // Reset button
                Button {
                    resetToDefaults()
                } label: {
                    Label("home.customize.resetDefaults", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                }
                .padding(.top, 12)
                .padding(.horizontal, 50)
            }
            .padding(.vertical, 40)
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            configs = HomeRowConfig.loadFromStorage()
        }
    }

    private var enabledRows: [HomeRowConfig] {
        configs.filter(\.isEnabled).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var disabledRows: [HomeRowConfig] {
        configs.filter { !$0.isEnabled }
    }

    // MARK: - Actions

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

    private func moveUp(_ type: HomeRowType) {
        var enabled = enabledRows
        guard let currentIndex = enabled.firstIndex(where: { $0.type == type }), currentIndex > 0 else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            enabled.swapAt(currentIndex, currentIndex - 1)
            applyOrder(enabled)
        }
    }

    private func moveDown(_ type: HomeRowType) {
        var enabled = enabledRows
        guard let currentIndex = enabled.firstIndex(where: { $0.type == type }), currentIndex < enabled.count - 1 else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            enabled.swapAt(currentIndex, currentIndex + 1)
            applyOrder(enabled)
        }
    }

    private func applyOrder(_ ordered: [HomeRowConfig]) {
        for (newIndex, row) in ordered.enumerated() {
            if let configIndex = configs.firstIndex(where: { $0.type == row.type }) {
                configs[configIndex].sortOrder = newIndex
            }
        }
        save()
    }

    private func resetToDefaults() {
        withAnimation(.easeInOut(duration: 0.25)) {
            configs = HomeRowConfig.defaultConfig()
        }
        save()
    }

    private func save() {
        HomeRowConfig.saveToStorage(configs)
        NotificationCenter.default.post(name: .homeConfigDidChange, object: nil)
    }
}

// MARK: - Active Row (with move/remove buttons)

struct ActiveRowItem: View {
    let config: HomeRowConfig
    let index: Int
    let isFirst: Bool
    let isLast: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Row info
            Image(systemName: config.type.systemImage)
                .font(.title3)
                .frame(width: 40, alignment: .center)
                .foregroundStyle(.tint)

            Text(config.type.localizedTitle)
                .font(.body)

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                ActionButton(systemImage: "chevron.up", enabled: !isFirst) {
                    onMoveUp()
                }

                ActionButton(systemImage: "chevron.down", enabled: !isLast) {
                    onMoveDown()
                }

                ActionButton(systemImage: "minus.circle.fill", enabled: true, tint: .red) {
                    onRemove()
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.05))
        )
    }
}

// MARK: - Inactive Row (with add button)

struct InactiveRowItem: View {
    let config: HomeRowConfig
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: config.type.systemImage)
                .font(.title3)
                .frame(width: 40, alignment: .center)
                .foregroundStyle(.tertiary)

            Text(config.type.localizedTitle)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            ActionButton(systemImage: "plus.circle.fill", enabled: true, tint: .green) {
                onAdd()
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(0.03))
        )
    }
}

// MARK: - Small Action Button

struct ActionButton: View {
    let systemImage: String
    let enabled: Bool
    var tint: Color = .white
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 44, height: 44)
                .foregroundStyle(enabled ? (isFocused ? tint : tint.opacity(0.6)) : .white.opacity(0.15))
                .background(
                    Circle()
                        .fill(isFocused ? .white.opacity(0.2) : .clear)
                )
                .scaleEffect(isFocused ? 1.15 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .disabled(!enabled)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let homeConfigDidChange = Notification.Name("homeConfigDidChange")
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
