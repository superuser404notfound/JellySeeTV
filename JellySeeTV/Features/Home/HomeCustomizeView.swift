import SwiftUI

struct HomeCustomizeView: View {
    @Binding var configs: [HomeRowConfig]
    var onSave: ([HomeRowConfig]) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(HomeRowType.allCases) { rowType in
                    if let config = configs.first(where: { $0.type == rowType }) {
                        Button {
                            toggleRow(rowType)
                        } label: {
                            HStack {
                                Image(systemName: rowType.systemImage)
                                    .frame(width: 30)
                                    .foregroundStyle(config.isEnabled ? .primary : .tertiary)

                                Text(rowType.localizedTitle)
                                    .foregroundStyle(config.isEnabled ? .primary : .secondary)

                                Spacer()

                                if config.isEnabled {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("home.customize.title")
        }
    }

    private func toggleRow(_ type: HomeRowType) {
        if let index = configs.firstIndex(where: { $0.type == type }) {
            configs[index].isEnabled.toggle()
            onSave(configs)
        }
    }
}
