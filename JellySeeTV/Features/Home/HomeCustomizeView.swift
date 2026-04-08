import SwiftUI

struct HomeCustomizeView: View {
    @State private var configs: [HomeRowConfig] = HomeRowConfig.loadFromStorage()

    private let displayOrder: [HomeRowType] = [
        .continueWatching,
        .nextUp,
        .latestMovies,
        .latestShows,
        .favorites,
        .genres,
        .topRatedMovies,
        .topRatedShows,
        .recentlyAdded,
        .allMovies,
        .allSeries,
        .studios,
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
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

                VStack(spacing: 2) {
                    ForEach(displayOrder) { type in
                        if let index = configs.firstIndex(where: { $0.type == type }) {
                            CategoryToggleRow(
                                type: type,
                                isEnabled: configs[index].isEnabled
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    configs[index].isEnabled.toggle()
                                }
                                save()
                            }
                        }
                    }
                }
                .padding(.horizontal, 50)

                Button {
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

    private func save() {
        // Assign sort order based on display order (enabled items only)
        var order = 0
        for type in displayOrder {
            if let index = configs.firstIndex(where: { $0.type == type }), configs[index].isEnabled {
                configs[index].sortOrder = order
                order += 1
            }
        }
        HomeRowConfig.saveToStorage(configs)
        NotificationCenter.default.post(name: .homeConfigDidChange, object: nil)
    }
}

// MARK: - Toggle Row

struct CategoryToggleRow: View {
    let type: HomeRowType
    let isEnabled: Bool
    let onToggle: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 20) {
                Image(systemName: type.systemImage)
                    .font(.title3)
                    .frame(width: 40, alignment: .center)
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))

                Text(type.localizedTitle)
                    .font(.body)
                    .foregroundStyle(isEnabled ? .primary : .secondary)

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? .white.opacity(0.12) : .white.opacity(0.05))
            )
            .scaleEffect(isFocused ? 1.02 : 1.0)
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
