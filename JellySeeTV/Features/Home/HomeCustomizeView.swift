import SwiftUI

struct HomeCustomizeView: View {
    @State private var configs: [HomeRowConfig] = HomeRowConfig.loadFromStorage()
    @State private var isEditing = false
    @State private var grabbedType: HomeRowType?
    @State private var dropTargetIndex: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                activeSection
                if !disabledRows.isEmpty { inactiveSection }
                if !isEditing { resetButton }
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("home.customize.title")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isEditing {
                        grabbedType = nil
                        dropTargetIndex = nil
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
    }

    private var headerSubtitle: LocalizedStringKey {
        if !isEditing { return "home.customize.description" }
        if grabbedType != nil { return "home.customize.placeTip" }
        return "home.customize.editTip"
    }

    // MARK: - Active Section

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("home.customize.active", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 50)

            VStack(spacing: 0) {
                ForEach(Array(enabledRows.enumerated()), id: \.element.id) { index, config in
                    VStack(spacing: 0) {
                        // Drop indicator line ABOVE this row
                        if grabbedType != nil && dropTargetIndex == index {
                            dropIndicator
                        }

                        HStack(spacing: 0) {
                            // Main row button (for grab/place)
                            rowLabel(config: config, isActive: true)
                                .onTapGesture {
                                    handleTap(config: config, index: index)
                                }

                            // Toggle button (edit mode only)
                            if isEditing {
                                ToggleButton(isActive: true) {
                                    toggle(config.type)
                                }
                            }
                        }

                        // Drop indicator AFTER last row
                        if grabbedType != nil && index == enabledRows.count - 1 && dropTargetIndex == enabledRows.count {
                            dropIndicator
                        }
                    }
                }
            }
            .padding(.horizontal, 50)
        }
    }

    // MARK: - Inactive Section

    private var inactiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("home.customize.inactive", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 50)

            VStack(spacing: 0) {
                ForEach(disabledRows) { config in
                    HStack(spacing: 0) {
                        rowLabel(config: config, isActive: false)

                        if isEditing {
                            ToggleButton(isActive: false) {
                                toggle(config.type)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 50)
        }
    }

    // MARK: - Row Label

    private func rowLabel(config: HomeRowConfig, isActive: Bool) -> some View {
        CategoryRowLabel(
            config: config,
            isActive: isActive,
            isGrabbed: grabbedType == config.type,
            isEditing: isEditing
        )
    }

    // MARK: - Drop Indicator

    private var dropIndicator: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
            Rectangle().fill(Color.accentColor).frame(height: 2)
            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button {
            resetToDefaults()
        } label: {
            Label("home.customize.resetDefaults", systemImage: "arrow.counterclockwise")
                .font(.subheadline)
        }
        .padding(.top, 12)
        .padding(.horizontal, 50)
    }

    // MARK: - Data

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
            guard grabbed != config.type else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    grabbedType = nil
                    dropTargetIndex = nil
                }
                return
            }

            withAnimation(.easeInOut(duration: 0.25)) {
                placeGrabbed(grabbed, at: index)
                grabbedType = nil
                dropTargetIndex = nil
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                grabbedType = config.type
                // Show drop indicator at the grabbed item's position
                dropTargetIndex = index
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
            grabbedType = nil
            dropTargetIndex = nil
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

// MARK: - Category Row Label (focusable, shows grab state)

struct CategoryRowLabel: View {
    let config: HomeRowConfig
    let isActive: Bool
    let isGrabbed: Bool
    let isEditing: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: config.type.systemImage)
                .font(.title3)
                .frame(width: 40, alignment: .center)
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

            Text(config.type.localizedTitle)
                .font(.body)
                .foregroundStyle(isActive ? .primary : .secondary)

            Spacer()
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
        .opacity(isGrabbed ? 0.6 : 1.0)
        .focusable(isEditing && isActive)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: isGrabbed)
    }

    private var rowBackground: Color {
        if isGrabbed { return Color.accentColor.opacity(0.15) }
        if isFocused { return .white.opacity(0.12) }
        return isActive ? .white.opacity(0.05) : .white.opacity(0.02)
    }
}

// MARK: - Toggle Button (plus/minus, separately focusable)

struct ToggleButton: View {
    let isActive: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: isActive ? "minus.circle.fill" : "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(isActive ? .red : .green)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(isFocused ? .white.opacity(0.2) : .clear)
                )
                .scaleEffect(isFocused ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
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
