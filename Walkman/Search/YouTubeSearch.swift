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

/// The song credited in a video's "Music" section, for licensed music.
///
/// It names what plays *in* the video, which isn't always what the video is:
/// a tutorial credits its background track, a DJ set one of the tracks it
/// plays. Callers check it against the title before trusting it.
struct MusicCredit: Equatable {
    let song: String
    let artist: String
    let album: String?
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

    private static let base = URL(string: "https://www.youtube.com/youtubei/v1/")!
    private static let clientVersion = "2.20250101.00.00"
    /// The "Type: Video" filter, so channels, playlists and shelves stay out.
    private static let videosOnly = "EgIQAQ%3D%3D"

    var session: URLSession = .shared

    func search(_ query: String) async throws -> SearchPage {
        try Self.parse(await post("search", ["query": query, "params": Self.videosOnly]))
    }

    func more(after continuation: String) async throws -> SearchPage {
        try Self.parse(await post("search", ["continuation": continuation]))
    }

    /// A known video as search shows it — with its channel and length — when
    /// only its ID and title are to hand: looked for by title, then by ID.
    func video(id: String, title: String) async throws -> SearchResult? {
        for query in title == id ? [id] : [title, id] {
            if let match = try await search(query).results.first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    /// The song YouTube credits in the video's "Music" section, if it has one.
    func musicCredit(for videoID: String) async throws -> MusicCredit? {
        // Asked for in English: the section is found by its "Music" heading.
        try Self.parseMusicCredit(await post("next", ["videoId": videoID], language: "en"))
    }

    private func post(_ endpoint: String, _ body: [String: Any], language: String? = nil) async throws -> Data {
        let locale = Locale.current
        var payload = body
        payload["context"] = [
            "client": [
                "clientName": "WEB",
                "clientVersion": Self.clientVersion,
                "hl": language ?? locale.language.languageCode?.identifier ?? "en",
                "gl": locale.region?.identifier ?? "US"
            ]
        ]

        var components = URLComponents(url: Self.base.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw SearchError.badResponse(status)
        }
        return data
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

    /// The first card under a "Music" heading in the watch page's description.
    static func parseMusicCredit(_ data: Data) throws -> MusicCredit? {
        let json = try JSONSerialization.jsonObject(with: data)
        var credit: MusicCredit?

        walk(json) { key, value in
            guard credit == nil, key == "horizontalCardListRenderer" else { return }
            let header = (value["header"] as? [String: Any])?["richListHeaderRenderer"] as? [String: Any]
            guard text(header?["title"]) == "Music",
                  let cards = value["cards"] as? [[String: Any]] else { return }

            for card in cards {
                guard let model = card["videoAttributeViewModel"] as? [String: Any],
                      let song = model["title"] as? String, !song.isEmpty,
                      let artist = model["subtitle"] as? String, !artist.isEmpty else { continue }
                let album = (model["secondarySubtitle"] as? [String: Any])?["content"] as? String
                credit = MusicCredit(song: song, artist: artist, album: album?.isEmpty == false ? album : nil)
                return
            }
        }
        return credit
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
