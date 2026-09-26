import Foundation

// Scores song identification against hand-labelled YouTube videos.
// Built from the app's own sources by run.sh, so it measures the real code.

struct Row: Decodable {
    struct Music: Decodable { let song: String?; let artist: String?; let album: String? }
    struct Expected: Decodable { let artists: [String]; let track: String }
    let query: String, id: String, title: String, channel: String, duration: String
    let music: Music?
    let expected: Expected?
}

typealias Strategy = (SearchResult, MusicCredit?) async -> LastFMTrack?

let lastFM = LastFM(apiKey: ProcessInfo.processInfo.environment["LASTFM_API_KEY"] ?? "")

func app(_ video: SearchResult, _ credit: MusicCredit?) async -> SongIdentifier.Outcome? {
    try? await SongIdentifier.identify(video, credit: credit) { track, artist in
        try await lastFM.searchTracks(track, artist: artist, limit: 5)
    }
}

var modelSeconds: [Double] = []

/// The on-device model's reading, checked against Last.fm: a real track, not
/// a scrobbled video title, with enough listeners to believe in — the model
/// can be confidently wrong about an artist.
func model(_ video: SearchResult, _ credit: MusicCredit?) async -> LastFMTrack? {
    let start = Date()
    let reading = try? await OnDeviceModel.read(video, credit: credit)
    modelSeconds.append(Date().timeIntervalSince(start))
    guard let reading, reading.isSingleSong, !reading.track.isEmpty else { return nil }
    let found = (try? await lastFM.searchTracks(reading.track, artist: reading.artist.isEmpty ? nil : reading.artist, limit: 5)) ?? []
    return found.first { !TrackMatching.looksLikeVideoTitle($0.name, searchedFor: reading.track) && ($0.listeners ?? 0) >= 1000 }
}

/// Add a strategy here to compare it with the app's.
var strategies: [(name: String, identify: Strategy)] = [
    ("app", { video, credit in
        if case .song(let track) = await app(video, credit) { return track }
        return nil
    })
]
if OnDeviceModel.isAvailable {
    strategies.append(("model", { video, credit in await model(video, credit) }))
    // The rules first; the model only where they found nothing. Sets and
    // streams stay rejected on length alone.
    strategies.append(("app+model", { video, credit in
        switch await app(video, credit) {
        case .song(let track): return track
        case .notASingleSong: return nil
        case .unknown, nil: return await model(video, credit)
        }
    }))
}

enum Verdict: String, CaseIterable { case right, wrong, missed, falsePositive = "false+" }

func overlap(_ needle: String, _ haystack: String) -> Double { TrackMatching.overlap(of: needle, in: haystack) }

func verdict(_ row: Row, _ found: LastFMTrack?) -> Verdict {
    guard let expected = row.expected else { return found == nil ? .right : .falsePositive }
    guard let found else { return .missed }
    let artist = TrackMatching.normalized(found.artist)
    let artistOK = expected.artists.map(TrackMatching.normalized).contains { artist.contains($0) || $0.contains(artist) }
    // The name must be the song and not much more: "Debussy: Clair de lune | …" is a scrobbled video, not the piece.
    let name = TrackMatching.bareTrack(found.name, dropSubtitles: true)
    let trackOK = expected.track.split(separator: "|").contains { overlap(String($0), name) >= 0.8 && overlap(name, String($0)) >= 0.6 }
    return artistOK && trackOK ? .right : .wrong
}

let paths = CommandLine.arguments.dropFirst()
var totals: [String: [Verdict: Int]] = [:]

for path in paths {
    let rows = try JSONDecoder().decode([Row].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    print("\n== \(path) (\(rows.count))")
    for row in rows {
        let video = SearchResult(id: row.id, title: row.title, channel: row.channel, snippet: "",
                                 duration: row.duration, viewCount: "", published: "", thumbnailURL: nil)
        let credit = row.music.flatMap { m -> MusicCredit? in
            guard let song = m.song, let artist = m.artist, !song.isEmpty, !artist.isEmpty else { return nil }
            return MusicCredit(song: song, artist: artist, album: m.album)
        }
        var line = row.query.padding(toLength: 26, withPad: " ", startingAt: 0)
        for strategy in strategies {
            let found = await strategy.identify(video, credit)
            let v = verdict(row, found)
            totals[strategy.name, default: [:]][v, default: 0] += 1
            let what = found.map { "\($0.artist) — \($0.name)" } ?? "∅"
            if ProcessInfo.processInfo.environment["FULL_NAMES"] != nil, let found { print("  [\(strategy.name)] \(row.query): \(found.artist) — \(found.name)") }
            line += " | \(strategy.name) \(v.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(what.prefix(26).padding(toLength: 26, withPad: " ", startingAt: 0))"
        }
        print(line)
    }
}

print()
if !modelSeconds.isEmpty {
    let sorted = modelSeconds.sorted()
    print(String(format: "model: %d calls, median %.2fs, slowest %.2fs", sorted.count, sorted[sorted.count / 2], sorted.last!))
}
for strategy in strategies {
    let t = totals[strategy.name, default: [:]]
    print("\(strategy.name): " + Verdict.allCases.map { "\($0.rawValue) \(t[$0, default: 0])" }.joined(separator: ", "))
}
