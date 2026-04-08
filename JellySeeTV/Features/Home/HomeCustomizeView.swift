import SwiftUI

struct HomeCustomizeView: View {
    @State private var configs: [HomeRowConfig] = HomeRowConfig.loadFromStorage()

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("home.customize.description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 50)

                // Active rows
                VStack(alignment: .leading, spacing: 12) {
                    Label("home.customize.active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 50)

                    VStack(spacing: 4) {
                        ForEach(Array(enabledRows.enumerated()), id: \.element.id) { index, config in
                            CustomizeRowItem(
                                config: config,
                                index: index,
                                isActive: true,
                                isFirst: index == 0,
                                isLast: index == enabledRows.count - 1,
                                onToggle: { toggle(config.type) },
                                onMoveUp: { moveUp(config.type) },
                                onMoveDown: { moveDown(config.type) }
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
                                CustomizeRowItem(
                                    config: config,
                                    index: nil,
                                    isActive: false,
                                    isFirst: false,
                                    isLast: false,
                                    onToggle: { toggle(config.type) },
                                    onMoveUp: {},
                                    onMoveDown: {}
                                )
                            }
                        }
                        .padding(.horizontal, 50)
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .navigationTitle("home.customize.title")
        .toolbar(.hidden, for: .tabBar)
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

    private func save() {
        HomeRowConfig.saveToStorage(configs)
        NotificationCenter.default.post(name: .homeConfigDidChange, object: nil)
    }
}

// MARK: - Row Item

struct CustomizeRowItem: View {
    let config: HomeRowConfig
    let index: Int?
    let isActive: Bool
    let isFirst: Bool
    let isLast: Bool
    let onToggle: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        Button {
            // No-op: all actions via context menu
        } label: {
            HStack(spacing: 16) {
                Image(systemName: config.type.systemImage)
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

                Text(config.type.localizedTitle)
                    .font(.body)

                Spacer()

                if isActive, let index {
                    Text("\(index + 1)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
        }
        .buttonStyle(CustomizeRowButtonStyle())
        .contextMenu {
            contextMenuItems
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if isActive {
            if !isFirst {
                Button {
                    onMoveUp()
                } label: {
                    Label("home.customize.moveUp", systemImage: "arrow.up")
                }
            }

            if !isLast {
                Button {
                    onMoveDown()
                } label: {
                    Label("home.customize.moveDown", systemImage: "arrow.down")
                }
            }

            Divider()

            Button(role: .destructive) {
                onToggle()
            } label: {
                Label("home.customize.remove", systemImage: "minus.circle")
            }
        } else {
            Button {
                onToggle()
            } label: {
                Label("home.customize.add", systemImage: "plus.circle")
            }
        }
    }
}

// MARK: - Button Style

struct CustomizeRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? .white.opacity(0.15) : .white.opacity(0.05))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
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
