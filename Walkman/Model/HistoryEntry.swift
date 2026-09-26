import Foundation

/// One video the user has played, as persisted in the history store.
struct HistoryEntry: Identifiable, Codable, Hashable {

    /// The YouTube video ID, which also uniquely identifies the entry.
    let id: String
    var title: String
    var thumbnailURL: URL?
    /// When it was last played — or filed, for an entry that has never been played.
    var lastPlayedAt: Date
    /// Zero for an entry filed from search and not yet played.
    var playCount: Int

    init(id: String, title: String, thumbnailURL: URL? = nil, lastPlayedAt: Date = .now, playCount: Int = 1) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL ?? Self.defaultThumbnailURL(for: id)
        self.lastPlayedAt = lastPlayedAt
        self.playCount = playCount
    }

    /// YouTube serves a thumbnail at a predictable URL for every video, so history
    /// entries have artwork even before metadata extraction finishes.
    static func defaultThumbnailURL(for videoID: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    /// Matches free-text search against the title and the ID.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(query) || id.localizedCaseInsensitiveContains(query)
    }
}
