import SwiftUI

struct HomeCustomizeView: View {
    @State private var configs: [HomeRowConfig] = HomeRowConfig.loadFromStorage()
    @State private var isEditing = false
    @State private var grabbedType: HomeRowType?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("home.customize.title")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(isEditing
                             ? (grabbedType != nil ? "home.customize.placeTip" : "home.customize.editTip")
                             : "home.customize.description")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isEditing {
                                grabbedType = nil
                                isEditing = false
                            } else {
                                isEditing = true
                            }
                        }
                    } label: {
                        Text(isEditing ? "home.customize.done" : "home.customize.edit")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
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
                            CategoryRow(
                                config: config,
                                isEditing: isEditing,
                                isGrabbed: grabbedType == config.type,
                                isActive: true,
                                onTap: { handleTap(config: config, index: index) },
                                onToggle: { toggle(config.type) }
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
                                CategoryRow(
                                    config: config,
                                    isEditing: isEditing,
                                    isGrabbed: false,
                                    isActive: false,
                                    onTap: {},
                                    onToggle: { toggle(config.type) }
                                )
                            }
                        }
                        .padding(.horizontal, 50)
                    }
                }

                // Reset button
                if !isEditing {
                    Button {
                        resetToDefaults()
                    } label: {
                        Label("home.customize.resetDefaults", systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 50)
                }
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

    // MARK: - Tap Logic

    private func handleTap(config: HomeRowConfig, index: Int) {
        guard isEditing else { return }

        if let grabbed = grabbedType {
            // Place the grabbed item at this position
            guard grabbed != config.type else {
                // Tapped same item -- deselect
                withAnimation(.easeInOut(duration: 0.2)) { grabbedType = nil }
                return
            }

            withAnimation(.easeInOut(duration: 0.25)) {
                placeGrabbed(grabbed, at: index)
                grabbedType = nil
            }
        } else {
            // Grab this item
            withAnimation(.easeInOut(duration: 0.2)) {
                grabbedType = config.type
            }
        }
    }

    private func placeGrabbed(_ type: HomeRowType, at targetIndex: Int) {
        var enabled = enabledRows
        guard let sourceIndex = enabled.firstIndex(where: { $0.type == type }) else { return }

        let item = enabled.remove(at: sourceIndex)
        let insertAt = min(targetIndex, enabled.count)
        enabled.insert(item, at: insertAt)

        for (newIndex, row) in enabled.enumerated() {
            if let configIndex = configs.firstIndex(where: { $0.type == row.type }) {
                configs[configIndex].sortOrder = newIndex
            }
        }
        save()
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

// MARK: - Category Row

struct CategoryRow: View {
    let config: HomeRowConfig
    let isEditing: Bool
    let isGrabbed: Bool
    let isActive: Bool
    let onTap: () -> Void
    let onToggle: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            if isEditing && isActive {
                onTap()
            }
        } label: {
            HStack(spacing: 20) {
                Image(systemName: config.type.systemImage)
                    .font(.title3)
                    .frame(width: 40, alignment: .center)
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

                Text(config.type.localizedTitle)
                    .font(.body)
                    .foregroundStyle(isActive ? .primary : .secondary)

                Spacer()

                if isEditing {
                    toggleButton
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isGrabbed ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isGrabbed ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isGrabbed)
        }
        .buttonStyle(CategoryRowButtonStyle(isFocused: _isFocused))
        .focused($isFocused)
    }

    private var rowBackground: Color {
        if isGrabbed {
            return Color.accentColor.opacity(0.15)
        }
        if isFocused {
            return .white.opacity(0.12)
        }
        return isActive ? .white.opacity(0.05) : .white.opacity(0.02)
    }

    @ViewBuilder
    private var toggleButton: some View {
        Button {
            onToggle()
        } label: {
            Image(systemName: isActive ? "minus.circle.fill" : "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(isActive ? .red : .green)
        }
        .buttonStyle(.plain)
    }
}

struct CategoryRowButtonStyle: ButtonStyle {
    @FocusState var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
