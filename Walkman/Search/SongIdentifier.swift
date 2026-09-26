import Foundation

/// Works out which song a YouTube video is, as Last.fm knows it — or that it
/// isn't one song at all.
///
/// Last.fm's search can't be taken at its word: people scrobble whatever
/// YouTube plays, so it holds "tracks" like "Marques Brownlee — iPhone Review"
/// and "HYBE LABELS — BTS 'Dynamite' Official MV". Every answer is checked
/// against what the video itself says. The rules were tuned and checked
/// against 65 labelled videos; see Tools/SongIDEval.
enum SongIdentifier {

    enum Outcome: Equatable {
        case song(LastFMTrack)
        /// Too long, or live: a set, a concert, a stream.
        case notASingleSong
        /// Nothing trustworthy found.
        case unknown
    }

    /// Longer than this, a video is a set or a concert rather than one song.
    static let longestSong: TimeInterval = 12 * 60

    /// Looks up tracks on Last.fm: a track name and an optional artist.
    typealias Search = (_ track: String, _ artist: String?) async throws -> [LastFMTrack]

    static func identify(_ video: SearchResult, credit: MusicCredit?, search: Search) async throws -> Outcome {
        guard let length = TrackMatching.seconds(fromDisplay: video.duration), length <= longestSong else {
            return .notASingleSong
        }

        // 1. YouTube's own credit, when it's plausibly what the video is.
        if let credit = accepted(credit, for: video),
           let found = try await firstGenuine(credit.track, artist: credit.artist,
                                              minListeners: credit.isVouchedFor ? 0 : 5000, search: search) {
            return .song(found)
        }

        // 2. The title, read as "Artist - Song" or with the artist's channel.
        let guess = TrackMatching.guess(title: video.title, channel: video.channel)
        let track = TrackMatching.bareTrack(guess.track)
        if let artist = guess.artist,
           let found = try await firstGenuine(track, artist: artist, minListeners: 0, search: search) {
            return .song(found)
        }

        // 3. With no artist to go on, only an answer whose artist the video names.
        var candidates = [track]
        if let quoted = TrackMatching.quoted(in: video.title) {
            candidates.insert(TrackMatching.bareTrack(quoted), at: 0)
        }
        for candidate in candidates {
            if let found = try await firstGenuine(candidate, artist: nil, minListeners: 500, search: search),
               TrackMatching.names(found.artist, video: video) {
                return .song(found)
            }
        }
        return .unknown
    }

    // MARK: - YouTube's credit

    struct AcceptedCredit: Equatable {
        let artist: String
        let track: String
        /// The video names the artist, so the credit needs no further proof.
        let isVouchedFor: Bool
    }

    /// The credit, unless it's clearly about something else — background music
    /// in a tutorial, one track out of a set.
    static func accepted(_ credit: MusicCredit?, for video: SearchResult) -> AcceptedCredit? {
        guard let credit else { return nil }
        let track = TrackMatching.bareTrack(credit.song, dropSubtitles: true)
        let artist = TrackMatching.leadArtist(credit.artist)
        guard !track.isEmpty, !artist.isEmpty else { return nil }

        let vouched = TrackMatching.names(artist, video: video)
        let songInTitle = TrackMatching.overlap(of: track, in: video.title) >= 0.6
        // A title in another script can't be compared word for word with a
        // credit in Latin letters ("残響散歌" vs "Zankyosanka").
        guard songInTitle || vouched || TrackMatching.isMostlyNonLatin(video.title) else { return nil }
        return AcceptedCredit(artist: artist, track: track, isVouchedFor: vouched)
    }

    // MARK: - Last.fm

    /// The first of Last.fm's answers that's a real track: not a scrobbled
    /// video title, and listened to enough to be believed.
    private static func firstGenuine(_ track: String, artist: String?, minListeners: Int, search: Search) async throws -> LastFMTrack? {
        guard !track.isEmpty else { return nil }
        return try await search(track, artist).first {
            !TrackMatching.looksLikeVideoTitle($0.name, searchedFor: track) && ($0.listeners ?? 0) >= minListeners
        }
    }
}
