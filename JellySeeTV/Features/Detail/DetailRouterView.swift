import SwiftUI

struct DetailRouterView: View {
    let item: JellyfinItem

    var body: some View {
        Group {
            switch item.type {
            case .movie:
                MovieDetailView(item: item)
            case .series:
                SeriesDetailView(item: item)
            case .episode:
                MovieDetailView(item: item)
            case .boxSet:
                CollectionDetailView(item: item)
            default:
                MovieDetailView(item: item)
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}
