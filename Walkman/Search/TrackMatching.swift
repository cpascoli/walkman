import Foundation

/// Bridges YouTube's free-form titles and Last.fm's tidy artist/track pairs.
enum TrackMatching {

    // MARK: - YouTube title → song

    /// What a video's title most likely names. `artist` is nil when the title
    /// doesn't say and the channel isn't obviously the artist's.
    struct Guess: Equatable {
        let artist: String?
        let track: String
    }

    /// Words that mark a bracketed aside as packaging rather than part of the song.
    private static let packaging = [
        "official", "video", "audio", "lyric", "visuali", "remaster", "4k", "hd", "hq",
        "mv", "m/v", "clip", "explicit", "color coded", "full album"
    ]

    /// "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)"
    /// becomes Rick Astley / Never Gonna Give You Up.
    static func guess(title: String, channel: String) -> Guess {
        var cleaned = title

        // Drop bracketed asides that describe the upload, keeping ones like "(Live)" or "(feat. X)".
        for (open, close) in [("(", ")"), ("[", "]"), ("【", "】")] {
            let pattern = "\\s*" + NSRegularExpression.escapedPattern(for: open)
                + "([^" + NSRegularExpression.escapedPattern(for: close) + "]*)"
                + NSRegularExpression.escapedPattern(for: close)
            let regex = try! NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)).reversed() {
                guard let inner = Range(match.range(at: 1), in: cleaned),
                      let whole = Range(match.range, in: cleaned) else { continue }
                let aside = cleaned[inner].lowercased()
                if packaging.contains(where: aside.contains) {
                    cleaned.removeSubrange(whole)
                }
            }
        }

        // "Song | Channel Name" and the like.
        if let bar = cleaned.firstIndex(of: "|") {
            cleaned = String(cleaned[..<bar])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "-–—")))

        for separator in [" - ", " – ", " — "] {
            if let range = cleaned.range(of: separator) {
                let artist = cleaned[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let track = unquoted(cleaned[range.upperBound...].trimmingCharacters(in: .whitespaces))
                if !artist.isEmpty, !track.isEmpty {
                    return Guess(artist: artist, track: track)
                }
            }
        }

        return Guess(artist: artistName(fromChannel: channel), track: unquoted(cleaned))
    }

    /// "Rick Astley - Topic" and "RickAstleyVEVO" are the artist; anything else
    /// is just whoever uploaded it.
    static func artistName(fromChannel channel: String) -> String? {
        let trimmed = channel.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(" - Topic") {
            return String(trimmed.dropLast(" - Topic".count))
        }
        if trimmed.hasSuffix("VEVO"), trimmed.count > 4 {
            return String(trimmed.dropLast(4))
        }
        return nil
    }

    private static func unquoted(_ text: String) -> String {
        text.trimmingCharacters(in: .init(charactersIn: "\"'“”‘’"))
    }

    // MARK: - Last.fm track → YouTube video

    /// Versions of a song that aren't the song.
    private static let offVersions = [
        "live", "cover", "karaoke", "remix", "reaction", "instrumental", "8d", "slowed",
        "sped up", "nightcore", "tutorial", "lesson", "piano", "acoustic", "mashup",
        "extended", "hour", "loop", "bass boosted", "fan made", "fanmade", "parody"
    ]

    /// Picks the result that is most plausibly the track, or nil if none is.
    static func bestMatch(for track: LastFMTrack, in results: [SearchResult]) -> SearchResult? {
        results.enumerated()
            .compactMap { index, result in score(result, for: track, rank: index).map { (result, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Nil when the result doesn't name the track at all.
    static func score(_ result: SearchResult, for track: LastFMTrack, rank: Int) -> Double? {
        let title = normalized(result.title)
        let channel = normalized(result.channel)
        let name = normalized(stripAsides(track.name))
        let artist = normalized(track.artist)

        var score = 0.0

        if title.contains(name) {
            score += 3
        } else {
            let overlap = tokenOverlap(name, in: title)
            guard overlap >= 0.6 else { return nil }
            score += 2 * overlap
        }

        if title.contains(artist) || channel.contains(artist) {
            score += 2
        }
        // The artist's own channel, or YouTube's auto-generated "Topic" one.
        if channel == artist || channel == artist + " topic" || channel == artist.replacingOccurrences(of: " ", with: "") + "vevo" {
            score += 1.5
        }

        if let expected = track.duration, let actual = seconds(fromDisplay: result.duration) {
            switch abs(actual - expected) {
            case ...10: score += 2
            case ...30: score += 1
            case 120...: score -= 2
            default: break
            }
        }

        // Whole words only — "Dead or Alive" isn't a live version. A word the
        // song or artist itself uses doesn't count against it either.
        let paddedTitle = " \(title) "
        let own = " \(normalized(track.name)) \(artist) "
        for word in offVersions where paddedTitle.contains(" \(word) ") && !own.contains(" \(word) ") {
            score -= 3
        }

        // YouTube's own ranking is a decent tiebreaker.
        score -= Double(rank) * 0.1
        return score
    }

    /// "3:42" → 222, "1:02:03" → 3723.
    static func seconds(fromDisplay text: String) -> TimeInterval? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard !parts.isEmpty, parts.count == text.split(separator: ":").count else { return nil }
        return TimeInterval(parts.reduce(0) { $0 * 60 + $1 })
    }

    // MARK: - Text

    /// Lowercased, accents folded, punctuation turned to single spaces.
    static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        let words = folded.unicodeScalars.split { !CharacterSet.alphanumerics.contains($0) }
        return words.map { String(String.UnicodeScalarView($0)) }.joined(separator: " ")
    }

    /// "Sweet Dreams (Are Made of This)" is often just "Sweet Dreams" on YouTube.
    private static func stripAsides(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression)
    }

    private static func tokenOverlap(_ needle: String, in haystack: String) -> Double {
        let wanted = Set(needle.split(separator: " "))
        guard !wanted.isEmpty else { return 0 }
        let present = Set(haystack.split(separator: " "))
        return Double(wanted.intersection(present).count) / Double(wanted.count)
    }
}
