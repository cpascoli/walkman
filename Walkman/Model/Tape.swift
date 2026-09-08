import Foundation

/// A named, ordered collection of videos — one cassette in the library.
struct Tape: Identifiable, Codable, Hashable {

    let id: UUID
    var name: String
    /// Track order, as video IDs. Deliberately just IDs: titles and artwork
    /// live in the recordings catalogue so they stay correct everywhere.
    var videoIDs: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, videoIDs: [String] = [], createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.name = name
        self.videoIDs = videoIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var trackCount: Int { videoIDs.count }

    func contains(_ videoID: String) -> Bool {
        videoIDs.contains(videoID)
    }
}
