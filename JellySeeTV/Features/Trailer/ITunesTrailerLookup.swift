import Foundation

/// Public Apple iTunes Search API as a native trailer source.
/// `previewUrl` on a movie hit is a direct MP4 stream that
/// AVPlayer plays without any external-app hand-off — the cleanest
/// way to keep trailer playback inside the app.
///
/// Coverage:
///   * Most Hollywood + many international films present on iTunes.
///   * TV shows: spotty (the API exposes seasons, not series-level
///     trailers), so callers should treat a nil result on TV as
///     "fall back to YouTube" rather than "no trailer at all".
///
/// Reference: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/
enum ITunesTrailerLookup {

    private static let endpoint = URL(string: "https://itunes.apple.com/search")!

    /// Best-effort fetch of a previewUrl for the given title/year.
    /// Returns `nil` on any failure (network, no match, no preview)
    /// so the caller can fall through to the next source.
    static func lookup(title: String, year: Int?) async -> URL? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "media", value: "movie"),
            URLQueryItem(name: "entity", value: "movie"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "country", value: storefrontCountry()),
        ]
        guard let url = components.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode)
            else { return nil }
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            let match = bestMatch(for: trimmed, year: year, in: decoded.results)

            #if DEBUG
            print("[Trailer] iTunes \(decoded.resultCount) hits for '\(trimmed)' (\(year ?? -1)) → match: \(match?.trackName ?? "—") preview: \(match?.previewUrl ?? "—")")
            #endif

            return match?.previewUrl.flatMap(URL.init(string:))
        } catch {
            #if DEBUG
            print("[Trailer] iTunes lookup failed for '\(trimmed)': \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Matching

    /// Picks the closest result. Priority:
    ///   1. Exact title match AND release year matches the request
    ///      (or off by ≤1, since some servers store post-release
    ///      content year vs. theatrical).
    ///   2. Exact title match, any year.
    ///   3. First result with a previewUrl.
    /// All steps require a non-empty previewUrl — a hit without one
    /// is useless to us.
    private static func bestMatch(
        for title: String,
        year: Int?,
        in results: [SearchResult]
    ) -> SearchResult? {
        let withPreview = results.filter { $0.previewUrl?.isEmpty == false }
        let normalizedTarget = normalize(title)

        if let year {
            if let exact = withPreview.first(where: {
                normalize($0.trackName ?? "") == normalizedTarget
                    && abs(($0.releaseYear ?? 0) - year) <= 1
            }) {
                return exact
            }
        }
        if let titleOnly = withPreview.first(where: {
            normalize($0.trackName ?? "") == normalizedTarget
        }) {
            return titleOnly
        }
        return withPreview.first
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    /// iTunes storefronts are per-country. Match the user's region
    /// when possible — a French user is far more likely to see "Le
    /// Cinquième Élément" listed under fr than us. Falls back to US
    /// (the largest catalog) when the device region isn't usable.
    private static func storefrontCountry() -> String {
        Locale.current.region?.identifier ?? "US"
    }
}

// MARK: - API model

private extension ITunesTrailerLookup {
    struct SearchResponse: Decodable {
        let resultCount: Int
        let results: [SearchResult]
    }

    struct SearchResult: Decodable {
        let trackName: String?
        let previewUrl: String?
        let releaseDate: String?

        var releaseYear: Int? {
            guard let releaseDate, releaseDate.count >= 4 else { return nil }
            return Int(releaseDate.prefix(4))
        }
    }
}
