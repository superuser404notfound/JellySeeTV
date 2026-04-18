import SwiftUI

enum AppTab: String, CaseIterable, Sendable {
    case home
    case catalog
    case search
    case settings

    var labelKey: LocalizedStringKey {
        switch self {
        case .home: "tab.home"
        case .catalog: "tab.catalog"
        case .search: "tab.search"
        case .settings: "tab.settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .catalog: "film.stack"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}

struct TabRootView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Tab(value: tab) {
                    tabContent(for: tab)
                } label: {
                    Label(tab.labelKey, systemImage: tab.systemImage)
                }
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .catalog:
            CatalogView()
        case .search:
            SearchView()
        case .settings:
            SettingsView()
        }
    }
}

struct PlaceholderTabView: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
