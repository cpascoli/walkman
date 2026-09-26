import Foundation
import Security

/// A track as Last.fm knows it.
struct LastFMTrack: Hashable {
    let artist: String
    let name: String
    /// How similar to the track asked about, 0...1. Nil outside `similarTracks`.
    var match: Double?
    /// Seconds, when Last.fm knows it — handy for telling the song from a mix.
    var duration: TimeInterval?
    /// How many people have scrobbled it. Search results only. Real tracks
    /// have plenty; scrobbled YouTube titles that aren't songs have few.
    var listeners: Int?
}

/// The two Last.fm calls the app needs. Both are read-only, so they want only
/// an API key; the shared secret is for signed calls and never leaves the
/// developer's machine.
struct LastFM {

    enum LastFMError: LocalizedError {
        case service(code: Int, message: String)
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .service(_, let message): "Last.fm: \(message)"
            case .badResponse(let status): "Last.fm didn't answer (HTTP \(status))"
            }
        }
    }

    private static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    let apiKey: String
    var session: URLSession = .shared

    /// Resolves free text to tracks, best match first.
    func searchTracks(_ track: String, artist: String? = nil, limit: Int = 5) async throws -> [LastFMTrack] {
        var parameters = ["method": "track.search", "track": track, "limit": String(limit)]
        if let artist, !artist.isEmpty { parameters["artist"] = artist }
        return Self.parseSearch(try await call(parameters))
    }

    /// Tracks like the given one, most similar first.
    func similarTracks(to track: LastFMTrack, limit: Int = 20) async throws -> [LastFMTrack] {
        Self.parseSimilar(try await call([
            "method": "track.getsimilar",
            "artist": track.artist,
            "track": track.name,
            "limit": String(limit),
            "autocorrect": "1"
        ]))
    }

    private func call(_ parameters: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = (parameters.merging(["api_key": apiKey, "format": "json"]) { $1 })
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        let (data, response) = try await session.data(from: components.url!)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        // Errors come back as JSON, often with a 4xx status alongside.
        if let code = json?["error"] as? Int {
            throw LastFMError.service(code: code, message: json?["message"] as? String ?? "error \(code)")
        }
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
            throw LastFMError.badResponse(status)
        }
        return json ?? [:]
    }

    // MARK: - Parsing

    /// Last.fm's JSON is converted from XML, so numbers are sometimes strings
    /// and a list of one sometimes arrives as a bare object.
    static func parseSearch(_ json: [String: Any]) -> [LastFMTrack] {
        let matches = (json["results"] as? [String: Any])?["trackmatches"] as? [String: Any]
        return list(matches?["track"]).compactMap { track in
            guard let name = track["name"] as? String,
                  let artist = track["artist"] as? String else { return nil }
            return LastFMTrack(artist: artist, name: name, listeners: number(track["listeners"]).map { Int($0) })
        }
    }

    static func parseSimilar(_ json: [String: Any]) -> [LastFMTrack] {
        let similar = json["similartracks"] as? [String: Any]
        return list(similar?["track"]).compactMap { track in
            guard let name = track["name"] as? String,
                  let artist = (track["artist"] as? [String: Any])?["name"] as? String else { return nil }
            let duration = number(track["duration"]).flatMap { $0 > 0 ? $0 : nil }
            return LastFMTrack(artist: artist, name: name, match: number(track["match"]), duration: duration)
        }
    }

    private static func list(_ node: Any?) -> [[String: Any]] {
        if let array = node as? [[String: Any]] { return array }
        if let single = node as? [String: Any] { return [single] }
        return []
    }

    private static func number(_ node: Any?) -> Double? {
        if let number = node as? NSNumber { return number.doubleValue }
        if let string = node as? String { return Double(string) }
        return nil
    }
}

// MARK: - Credentials

/// The user's Last.fm API key, kept in the Keychain so it never ends up in
/// the repository. `LASTFM_API_KEY` in the environment stands in for it, which
/// is how the UI tests get one.
enum LastFMCredentials {

    private static let service = "com.carlopascoli.walkman.lastfm"
    private static let account = "api-key"

    static var apiKey: String? {
        if let stored = read(), !stored.isEmpty { return stored }
        let environment = ProcessInfo.processInfo.environment["LASTFM_API_KEY"]
        return environment?.isEmpty == false ? environment : nil
    }

    /// The key saved in Settings, without the environment fallback.
    static var storedKey: String { read() ?? "" }

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !trimmed.isEmpty else { return }

        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
