import SwiftUI

struct HomeCustomizeView: View {
    @State private var configs: [HomeRowConfig] = HomeRowConfig.loadFromStorage()
    @State private var movingType: HomeRowType?

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Header
                VStack(spacing: 8) {
                    Text("home.customize.title")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(movingType != nil ? "home.customize.moveTip" : "home.customize.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 50)

                // Active rows
                VStack(alignment: .leading, spacing: 10) {
                    Label("home.customize.active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 50)

                    VStack(spacing: 2) {
                        ForEach(Array(enabledRows.enumerated()), id: \.element.id) { index, config in
                            ActiveCategoryRow(
                                type: config.type,
                                position: index + 1,
                                isMoving: movingType == config.type,
                                onSelect: {
                                    if let moving = movingType {
                                        // Place the moving row here
                                        if moving != config.type {
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                placeRow(moving, at: index)
                                            }
                                        }
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            movingType = nil
                                        }
                                    } else {
                                        // Start moving this row
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            movingType = config.type
                                        }
                                    }
                                },
                                onRemove: {
                                    movingType = nil
                                    toggle(config.type)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 50)
                }

                // Available rows
                if !disabledRows.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("home.customize.inactive", systemImage: "circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 50)

                        VStack(spacing: 2) {
                            ForEach(disabledRows) { config in
                                InactiveCategoryRow(type: config.type) {
                                    toggle(config.type)
                                }
                            }
                        }
                        .padding(.horizontal, 50)
                    }
                }

                // Reset
                Button {
                    movingType = nil
                    withAnimation(.easeInOut(duration: 0.25)) {
                        configs = HomeRowConfig.defaultConfig()
                    }
                    save()
                } label: {
                    Label("home.customize.resetDefaults", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                }
                .padding(.top, 8)
            }
            .padding(.vertical, 40)
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            configs = HomeRowConfig.loadFromStorage()
        }
    }

    // MARK: - Data

    private var enabledRows: [HomeRowConfig] {
        configs.filter(\.isEnabled).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var disabledRows: [HomeRowConfig] {
        configs.filter { !$0.isEnabled }
    }

    // MARK: - Actions

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

// MARK: - Active Row (position + move + remove)

struct ActiveCategoryRow: View {
    let type: HomeRowType
    let position: Int
    let isMoving: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    @FocusState private var rowFocused: Bool
    @FocusState private var removeFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Main row (tap to grab/place)
            Button { onSelect() } label: {
                HStack(spacing: 16) {
                    Text("\(position)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: 24)

                    Image(systemName: type.systemImage)
                        .font(.title3)
                        .frame(width: 36)
                        .foregroundStyle(.tint)

                    Text(type.localizedTitle)
                        .font(.body)

                    Spacer()

                    if isMoving {
                        Text("home.customize.moving")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isMoving ? Color.accentColor.opacity(0.12) : (rowFocused ? .white.opacity(0.12) : .white.opacity(0.05)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isMoving ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .focused($rowFocused)
            .scaleEffect(rowFocused ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: rowFocused)

            // Remove button
            Button { onRemove() } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .frame(width: 50, height: 50)
                    .scaleEffect(removeFocused ? 1.2 : 1.0)
                    .background(
                        Circle().fill(removeFocused ? .white.opacity(0.15) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .focused($removeFocused)
            .animation(.easeInOut(duration: 0.15), value: removeFocused)
        }
    }
}

// MARK: - Inactive Row (tap to add)

struct InactiveCategoryRow: View {
    let type: HomeRowType
    let onAdd: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Info
            HStack(spacing: 16) {
                Image(systemName: type.systemImage)
                    .font(.title3)
                    .frame(width: 36)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 44) // align with active rows (24 + 20 padding)

                Text(type.localizedTitle)
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

            // Add button
            Button { onAdd() } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 50, height: 50)
                    .scaleEffect(isFocused ? 1.2 : 1.0)
                    .background(
                        Circle().fill(isFocused ? .white.opacity(0.15) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .focused($isFocused)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
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
