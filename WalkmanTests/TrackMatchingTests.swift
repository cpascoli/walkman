import XCTest
@testable import Walkman

final class TrackMatchingTests: XCTestCase {

    // MARK: - Reading YouTube titles

    func testStripsPackagingAndSplitsArtistFromTrack() {
        XCTAssertEqual(
            TrackMatching.guess(title: "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)", channel: "Rick Astley"),
            .init(artist: "Rick Astley", track: "Never Gonna Give You Up")
        )
        XCTAssertEqual(
            TrackMatching.guess(title: "a-ha - Take On Me (Official Video) [Remastered in 4K]", channel: "a-ha"),
            .init(artist: "a-ha", track: "Take On Me")
        )
    }

    func testKeepsAsidesThatArePartOfTheSong() {
        XCTAssertEqual(
            TrackMatching.guess(title: "Daft Punk - Get Lucky (feat. Pharrell Williams)", channel: "Daft Punk").track,
            "Get Lucky (feat. Pharrell Williams)"
        )
    }

    func testUnquotesAndDropsTrailingBars() {
        XCTAssertEqual(
            TrackMatching.guess(title: "Toto - \"Africa\" | Classic Hits", channel: "Classic Hits"),
            .init(artist: "Toto", track: "Africa")
        )
    }

    func testFallsBackToTheChannelForTheArtist() {
        XCTAssertEqual(TrackMatching.guess(title: "Take On Me", channel: "a-ha - Topic"), .init(artist: "a-ha", track: "Take On Me"))
        XCTAssertEqual(TrackMatching.guess(title: "Hello", channel: "AdeleVEVO"), .init(artist: "Adele", track: "Hello"))
        XCTAssertEqual(TrackMatching.guess(title: "Me at the zoo", channel: "jawed"), .init(artist: nil, track: "Me at the zoo"))
    }

    // MARK: - Finding a track on YouTube

    private func result(_ id: String, _ title: String, channel: String, duration: String = "") -> SearchResult {
        SearchResult(id: id, title: title, channel: channel, snippet: "", duration: duration,
                     viewCount: "", published: "", thumbnailURL: nil)
    }

    func testPrefersTheOfficialUploadOverCoversAndLive() {
        let track = LastFMTrack(artist: "a-ha", name: "Take on Me", duration: 229)
        let results = [
            result("cover000001", "Take On Me - a-ha (Acoustic Cover)", channel: "Some Busker", duration: "3:10"),
            result("live0000001", "a-ha - Take On Me (Live at Wembley)", channel: "a-ha", duration: "4:40"),
            result("official001", "a-ha - Take On Me (Official Video) [Remastered in 4K]", channel: "a-ha", duration: "3:47")
        ]
        XCTAssertEqual(TrackMatching.bestMatch(for: track, in: results)?.id, "official001")
    }

    func testArtistNamesDontCountAsOffVersions() {
        // "Alive" isn't "live": Dead or Alive's own video must still win.
        let track = LastFMTrack(artist: "Dead or Alive", name: "You Spin Me Round (Like a Record)", duration: 195)
        let results = [
            result("karaoke0001", "You Spin Me Round - Karaoke Version", channel: "Sing King", duration: "3:16"),
            result("official001", "Dead Or Alive - You Spin Me Round (Like a Record) (Official Video)", channel: "Dead Or Alive", duration: "3:19")
        ]
        XCTAssertEqual(TrackMatching.bestMatch(for: track, in: results)?.id, "official001")
    }

    func testLengthBreaksTiesBetweenCuts() {
        let track = LastFMTrack(artist: "Eurythmics", name: "Sweet Dreams (Are Made of This)", duration: 216)
        let results = [
            result("longmix0001", "Eurythmics - Sweet Dreams (Are Made Of This)", channel: "Eurythmics", duration: "8:15"),
            result("single00001", "Eurythmics - Sweet Dreams (Are Made Of This)", channel: "Eurythmics", duration: "3:36")
        ]
        XCTAssertEqual(TrackMatching.bestMatch(for: track, in: results)?.id, "single00001")
    }

    func testRejectsResultsThatDontNameTheTrack() {
        let track = LastFMTrack(artist: "Bananarama", name: "Venus")
        let results = [result("other000001", "Top 10 80s dance moves", channel: "Retro TV")]
        XCTAssertNil(TrackMatching.bestMatch(for: track, in: results))
    }

    func testParsesDisplayDurations() {
        XCTAssertEqual(TrackMatching.seconds(fromDisplay: "3:42"), 222)
        XCTAssertEqual(TrackMatching.seconds(fromDisplay: "1:02:03"), 3723)
        XCTAssertNil(TrackMatching.seconds(fromDisplay: ""))
        XCTAssertNil(TrackMatching.seconds(fromDisplay: "LIVE"))
    }

    // MARK: - Last.fm responses

    func testParsesSimilarTracksWithMixedNumberTypes() throws {
        let json = try JSONSerialization.jsonObject(with: Data(#"""
        { "similartracks": { "track": [
            { "name": "Take on Me", "match": 0.953, "duration": 229, "artist": { "name": "a-ha" } },
            { "name": "Venus", "match": "0.474", "duration": "0", "artist": { "name": "Bananarama" } }
        ] } }
        """#.utf8)) as! [String: Any]

        let tracks = LastFM.parseSimilar(json)
        XCTAssertEqual(tracks.map(\.name), ["Take on Me", "Venus"])
        XCTAssertEqual(tracks[0].match, 0.953)
        XCTAssertEqual(tracks[0].duration, 229)
        XCTAssertEqual(tracks[1].match, 0.474)
        XCTAssertNil(tracks[1].duration, "Zero means Last.fm doesn't know")
    }

    func testParsesASingleSearchMatchSentAsAnObject() throws {
        let json = try JSONSerialization.jsonObject(with: Data(#"""
        { "results": { "trackmatches": { "track":
            { "name": "Never Gonna Give You Up", "artist": "Rick Astley", "listeners": "1459197" }
        } } }
        """#.utf8)) as! [String: Any]

        XCTAssertEqual(LastFM.parseSearch(json), [LastFMTrack(artist: "Rick Astley", name: "Never Gonna Give You Up")])
    }
}
