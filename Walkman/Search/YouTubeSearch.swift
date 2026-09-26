import Foundation

/// One video in a YouTube search result.
struct SearchResult: Identifiable, Hashable {

    /// The YouTube video ID.
    let id: String
    let title: String
    let channel: String
    /// The short description snippet YouTube shows under a result.
    let snippet: String
    /// Display length, e.g. "3:42". Empty for livestreams.
    let duration: String
    let viewCount: String
    let published: String
    let thumbnailURL: URL?
}

/// One page of results, plus the token that fetches the next.
struct SearchPage {
    let results: [SearchResult]
    let continuation: String?
}

/// Searches YouTube through the same InnerTube API the website uses.
///
/// There's no official, key-free search API, and asking for a Data API key would
/// be at odds with the rest of the app, which already relies on YouTubeKit's
/// unofficial extraction. The trade-off is the same: YouTube can change this
/// response at any time. The parser is written to survive that as far as it can
/// — it hunts for video renderers wherever they sit in the tree rather than
/// following one fixed path.
struct YouTubeSearch {

    enum SearchError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let status): "YouTube search failed (HTTP \(status))"
            }
        }
    }

    private static let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false")!
    private static let clientVersion = "2.20250101.00.00"
    /// The "Type: Video" filter, so channels, playlists and shelves stay out.
    private static let videosOnly = "EgIQAQ%3D%3D"

    var session: URLSession = .shared

    func search(_ query: String) async throws -> SearchPage {
        try await request(["query": query, "params": Self.videosOnly])
    }

    func more(after continuation: String) async throws -> SearchPage {
        try await request(["continuation": continuation])
    }

    private func request(_ body: [String: Any]) async throws -> SearchPage {
        let locale = Locale.current
        var payload = body
        payload["context"] = [
            "client": [
                "clientName": "WEB",
                "clientVersion": Self.clientVersion,
                "hl": locale.language.languageCode?.identifier ?? "en",
                "gl": locale.region?.identifier ?? "US"
            ]
        ]

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw SearchError.badResponse(status)
        }
        return try Self.parse(data)
    }

    // MARK: - Parsing

    static func parse(_ data: Data) throws -> SearchPage {
        let json = try JSONSerialization.jsonObject(with: data)
        var results: [SearchResult] = []
        var seen: Set<String> = []
        var continuation: String?

        walk(json) { key, value in
            switch key {
            case "videoRenderer":
                if let result = result(from: value), seen.insert(result.id).inserted {
                    results.append(result)
                }
            case "continuationCommand":
                if continuation == nil { continuation = value["token"] as? String }
            default:
                break
            }
        }
        return SearchPage(results: results, continuation: continuation)
    }

    /// Visits every keyed object in the tree. Doesn't descend into a video
    /// renderer, which can itself hold unrelated nested renderers.
    private static func walk(_ node: Any, visit: (String, [String: Any]) -> Void) {
        if let dictionary = node as? [String: Any] {
            for (key, value) in dictionary {
                if let object = value as? [String: Any] {
                    visit(key, object)
                    if key == "videoRenderer" { continue }
                }
                walk(value, visit: visit)
            }
        } else if let array = node as? [Any] {
            for element in array { walk(element, visit: visit) }
        }
    }

    private static func result(from renderer: [String: Any]) -> SearchResult? {
        guard let id = renderer["videoId"] as? String, YouTubeVideoID.isValid(id) else { return nil }

        let snippet = (renderer["detailedMetadataSnippets"] as? [[String: Any]])?
            .first.flatMap { text($0["snippetText"]) }
            ?? text(renderer["descriptionSnippet"])

        let thumbnails = (renderer["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
        let thumbnailURL = thumbnails?.first
            .flatMap { $0["url"] as? String }
            .flatMap(URL.init(string:))

        return SearchResult(
            id: id,
            title: text(renderer["title"]) ?? id,
            channel: text(renderer["ownerText"]) ?? text(renderer["longBylineText"]) ?? "",
            snippet: snippet ?? "",
            duration: text(renderer["lengthText"]) ?? "",
            viewCount: text(renderer["shortViewCountText"]) ?? text(renderer["viewCountText"]) ?? "",
            published: text(renderer["publishedTimeText"]) ?? "",
            thumbnailURL: thumbnailURL ?? HistoryEntry.defaultThumbnailURL(for: id)
        )
    }

    /// YouTube text is either `{simpleText}` or `{runs: [{text}]}`.
    private static func text(_ node: Any?) -> String? {
        guard let node = node as? [String: Any] else { return nil }
        if let simple = node["simpleText"] as? String { return simple }
        guard let runs = node["runs"] as? [[String: Any]] else { return nil }
        let joined = runs.compactMap { $0["text"] as? String }.joined()
        return joined.isEmpty ? nil : joined
    }
}
