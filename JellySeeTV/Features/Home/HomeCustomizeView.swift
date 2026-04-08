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

                    VStack(spacing: 2) {
                        ForEach(Array(enabledRows.enumerated()), id: \.element.id) { index, config in
                            rowItem(config: config, index: index, isActive: true)
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

                        VStack(spacing: 2) {
                            ForEach(disabledRows) { config in
                                rowItem(config: config, index: nil, isActive: false)
                            }
                        }
                        .padding(.horizontal, 50)
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .navigationTitle("home.customize.title")
    }

    private var enabledRows: [HomeRowConfig] {
        configs.filter(\.isEnabled).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var disabledRows: [HomeRowConfig] {
        configs.filter { !$0.isEnabled }
    }

    private func rowItem(config: HomeRowConfig, index: Int?, isActive: Bool) -> some View {
        Button {
            toggle(config.type)
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
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isActive {
                if let index, index > 0 {
                    Button {
                        moveUp(config.type)
                    } label: {
                        Label("home.customize.moveUp", systemImage: "arrow.up")
                    }
                }

                if let index, index < enabledRows.count - 1 {
                    Button {
                        moveDown(config.type)
                    } label: {
                        Label("home.customize.moveDown", systemImage: "arrow.down")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    toggle(config.type)
                } label: {
                    Label("home.customize.remove", systemImage: "minus.circle")
                }
            } else {
                Button {
                    toggle(config.type)
                } label: {
                    Label("home.customize.add", systemImage: "plus.circle")
                }
            }
        }
    }

    // MARK: - Actions

    private func toggle(_ type: HomeRowType) {
        guard let index = configs.firstIndex(where: { $0.type == type }) else { return }
        configs[index].isEnabled.toggle()

        if configs[index].isEnabled {
            let maxOrder = configs.filter(\.isEnabled).map(\.sortOrder).max() ?? 0
            configs[index].sortOrder = maxOrder + 1
        }

        save()
    }

    private func moveUp(_ type: HomeRowType) {
        var enabled = enabledRows
        guard let currentIndex = enabled.firstIndex(where: { $0.type == type }), currentIndex > 0 else { return }

        enabled.swapAt(currentIndex, currentIndex - 1)
        applyOrder(enabled)
    }

    private func moveDown(_ type: HomeRowType) {
        var enabled = enabledRows
        guard let currentIndex = enabled.firstIndex(where: { $0.type == type }), currentIndex < enabled.count - 1 else { return }

        enabled.swapAt(currentIndex, currentIndex + 1)
        applyOrder(enabled)
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
    }
}

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
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: "homeRowConfigs")
        }
    }
}
