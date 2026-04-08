import SwiftUI

struct HomeCustomizeView: View {
    @State private var configs: [HomeRowConfig] = HomeRowConfig.loadFromStorage()
    @State private var hasChanges = false

    var body: some View {
        List {
            Section {
                Text("home.customize.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(enabledRows) { config in
                    rowToggle(for: config.type)
                }
                .onMove { source, destination in
                    moveEnabledRow(from: source, to: destination)
                }
            } header: {
                Label("home.customize.active", systemImage: "checkmark.circle.fill")
            }

            if !disabledRows.isEmpty {
                Section {
                    ForEach(disabledRows) { config in
                        rowToggle(for: config.type)
                    }
                } header: {
                    Label("home.customize.inactive", systemImage: "circle")
                }
            }
        }
        .navigationTitle("home.customize.title")
    }

    private var enabledRows: [HomeRowConfig] {
        configs.filter(\.isEnabled).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var disabledRows: [HomeRowConfig] {
        configs.filter { !$0.isEnabled }
    }

    private func rowToggle(for type: HomeRowType) -> some View {
        let isEnabled = configs.first(where: { $0.type == type })?.isEnabled ?? false

        return Button {
            toggle(type)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: type.systemImage)
                    .font(.body)
                    .frame(width: 28)
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

                Text(type.localizedTitle)
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                Spacer()

                if isEnabled {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func toggle(_ type: HomeRowType) {
        guard let index = configs.firstIndex(where: { $0.type == type }) else { return }
        configs[index].isEnabled.toggle()

        if configs[index].isEnabled {
            let maxOrder = configs.filter(\.isEnabled).map(\.sortOrder).max() ?? 0
            configs[index].sortOrder = maxOrder + 1
        }

        save()
    }

    private func moveEnabledRow(from source: IndexSet, to destination: Int) {
        var enabled = enabledRows
        enabled.move(fromOffsets: source, toOffset: destination)

        for (newIndex, row) in enabled.enumerated() {
            if let configIndex = configs.firstIndex(where: { $0.type == row.type }) {
                configs[configIndex].sortOrder = newIndex
            }
        }

        save()
    }

    private func save() {
        HomeRowConfig.saveToStorage(configs)
        hasChanges = true
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
