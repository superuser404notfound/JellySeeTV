import SwiftUI

struct DetailRouterView: View {
    let item: JellyfinItem

    var body: some View {
        switch item.type {
        case .movie:
            MovieDetailView(item: item)
        case .series:
            SeriesDetailView(item: item)
        case .episode:
            MovieDetailView(item: item) // Episodes use similar layout to movies
        default:
            MovieDetailView(item: item)
        }
    }
}
