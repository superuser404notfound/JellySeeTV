import Foundation

/// Lean Jellyfin client scoped to what the TopShelf needs:
/// `/Items/Resume` and `/Shows/NextUp`. The main app's full client
/// is intentionally not shared here — pulling it in would drag the
/// whole DI graph (HTTPClient + 9 services + AppState) into the
/// extension's tight memory budget for one or two GET requests.
struct JellyfinAPI: Sendable {
    let session: SharedSession

    private static let deviceID: String = {
        // Stable per-extension device id so Jellyfin's session list
        // doesn't fill with one-off rows every time the system
        // refreshes the shelf. Lives in the shared App Group
        // UserDefaults so the main app's device id stays distinct.
        let defaults = UserDefaults(suiteName: "group.de.superuser404.JellySeeTV")
        let key = "topShelf.deviceID"
        if let existing = defaults?.string(forKey: key) { return existing }
        let new = UUID().uuidString
        defaults?.set(new, forKey: key)
        return new
    }()

    func resumeItems(limit: Int = 10) async throws -> [JellyfinItem] {
        let url = endpoint(
            path: "/Users/\(session.userID)/Items/Resume",
            query: [
                "MediaTypes": "Video",
                "Limit": "\(limit)",
                "Fields": Self.fields,
            ]
        )
        let response: ItemsResponse = try await get(url)
        return response.items ?? []
    }

    func nextUp(limit: Int = 10) async throws -> [JellyfinItem] {
        let url = endpoint(
            path: "/Shows/NextUp",
            query: [
                "UserId": session.userID,
                "Limit": "\(limit)",
                "Fields": Self.fields,
            ]
        )
        let response: ItemsResponse = try await get(url)
        return response.items ?? []
    }

    private func endpoint(path: String, query: [String: String]) -> URL {
        var base = session.baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        var components = URLComponents(string: base + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private var authHeader: String {
        let parts = [
            "Client=\"JellySeeTV\"",
            "Device=\"Apple TV\"",
            "DeviceId=\"\(Self.deviceID)\"",
            "Version=\"1.0\"",
            "Token=\"\(session.accessToken)\"",
        ]
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private static let fields = "ImageTags,BackdropImageTags,ParentBackdropImageTags,SeriesPrimaryImageTag"
}

private struct ItemsResponse: Decodable {
    let items: [JellyfinItem]?
    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}
