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

        cleaned = cutAtBar(cleaned)

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

    /// Drops "| Channel Name" and the like — but only a bar outside brackets,
    /// so "(TikTok Remix | Sped Up)" goes whole rather than being cut in half.
    private static func cutAtBar(_ text: String) -> String {
        var depth = 0
        for index in text.indices {
            switch text[index] {
            case "(", "[", "【", "「": depth += 1
            case ")", "]", "】", "」": depth = max(0, depth - 1)
            case "|" where depth == 0:
                return trimmed(String(text[..<index]))
            default: break
            }
        }
        return trimmed(text)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "-–—")))
    }

    /// The song on its own, for asking Last.fm: every bracketed aside dropped
    /// except a featured artist. With `dropSubtitles`, featured artists and
    /// " - Sequentia - Lacrimosa"-style tails go too — for YouTube's credits,
    /// which pile on edition details ("Get Lucky (Radio Edit - feat. …)").
    static func bareTrack(_ text: String, dropSubtitles: Bool = false) -> String {
        var bare = cutAtBar(text)
        let regex = try! NSRegularExpression(pattern: "\\s*[\\(\\[【]([^\\)\\]】]*)[\\)\\]】]")
        for match in regex.matches(in: bare, range: NSRange(bare.startIndex..., in: bare)).reversed() {
            guard let inner = Range(match.range(at: 1), in: bare), let whole = Range(match.range, in: bare) else { continue }
            let aside = bare[inner].lowercased()
            if !dropSubtitles, aside.hasPrefix("feat") || aside.hasPrefix("ft.") { continue }
            bare.removeSubrange(whole)
        }
        if dropSubtitles, let dash = bare.range(of: " - ") {
            bare = String(bare[..<dash.lowerBound])
        }
        return trimmed(unquoted(trimmed(bare)))
    }

    /// The first-named of several credited artists: "Calvin Harris, Rihanna",
    /// "BTS (방탄소년단)" and "Tommee Profitt x Skylar Grey" all lead with one.
    static func leadArtist(_ credit: String) -> String {
        var lead = bareTrack(credit, dropSubtitles: true)
        for separator in [", ", " & ", " x ", " X ", " feat. ", " ft. "] {
            if let range = lead.range(of: separator) {
                lead = String(lead[..<range.lowerBound])
            }
        }
        return lead.trimmingCharacters(in: .whitespaces)
    }

    /// Text in quotes: `Radiohead Perform "Creep" Live`, `TWICE "What is Love?" M/V`,
    /// `YOASOBI「夜に駆ける」`. Often the song, when there's no dash to split on.
    static func quoted(in title: String) -> String? {
        let regex = try! NSRegularExpression(pattern: "[\"“「'‘]([^\"”」'’]{2,60})[\"”」'’]")
        guard let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let inner = Range(match.range(at: 1), in: title) else { return nil }
        return String(title[inner])
    }

    /// Whether the video's title or channel names this artist.
    static func names(_ artist: String, video: SearchResult) -> Bool {
        overlap(of: artist, in: "\(video.title) \(video.channel)") >= 0.5
    }

    /// The share of `needle`'s words that appear in `haystack`.
    static func overlap(of needle: String, in haystack: String) -> Double {
        tokenOverlap(normalized(needle), in: normalized(haystack))
    }

    /// True for titles written mostly outside the Latin alphabet.
    static func isMostlyNonLatin(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        // Basic Latin through Latin Extended-B, so accents still count as Latin.
        let latin = letters.filter { $0.value < 0x250 }
        return Double(latin.count) / Double(letters.count) < 0.5
    }

    /// Words that give away a Last.fm "track" as a scrobbled video title.
    private static let videoTitleMarkers = [
        "official", "review", "full performance", "tiny desk", "concert", "live on", "radio",
        "boiler room", "m v", "mv", "lyrics", "lyric video", "tutorial", "compilation", "hd", "4k",
        "remaster", "remastered", "sped up", "slowed", "reverb", "nightcore", "8d audio"
    ]

    /// Whether a Last.fm track name is really a YouTube video's title. A marker
    /// the song itself contains doesn't count: "Radio Ga Ga" is a song.
    static func looksLikeVideoTitle(_ name: String, searchedFor track: String) -> Bool {
        if name.contains("|") || name.count > 60 { return true }
        let padded = " \(normalized(name)) "
        let own = " \(normalized(track)) "
        return videoTitleMarkers.contains { padded.contains(" \($0) ") && !own.contains(" \($0) ") }
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
