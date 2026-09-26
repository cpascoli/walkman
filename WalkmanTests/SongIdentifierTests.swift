import XCTest
@testable import Walkman

final class SongIdentifierTests: XCTestCase {

    // MARK: - Fixtures

    private func video(_ title: String, channel: String, duration: String = "3:45") -> SearchResult {
        SearchResult(id: "aaaaaaaaaaa", title: title, channel: channel, snippet: "", duration: duration,
                     viewCount: "", published: "", thumbnailURL: nil)
    }

    private func track(_ artist: String, _ name: String, listeners: Int = 100_000) -> LastFMTrack {
        LastFMTrack(artist: artist, name: name, listeners: listeners)
    }

    /// A stand-in for Last.fm: canned answers keyed by "track|artist".
    private func lastFM(_ answers: [String: [LastFMTrack]]) -> SongIdentifier.Search {
        { track, artist in answers["\(track)|\(artist ?? "")"] ?? [] }
    }

    private func identify(_ video: SearchResult, credit: MusicCredit? = nil,
                          _ answers: [String: [LastFMTrack]]) async throws -> SongIdentifier.Outcome {
        try await SongIdentifier.identify(video, credit: credit, search: lastFM(answers))
    }

    // MARK: - Not one song

    func testLongVideosAndStreamsAreNotSingleSongs() async throws {
        let set = video("Fred again.. | Boiler Room: London", channel: "Boiler Room", duration: "1:02:11")
        let stream = video("lofi hip hop radio 📚 beats to relax/study to", channel: "Lofi Girl", duration: "")
        let answers = ["Fred again..|": [track("Fred again..", "leavemealone")]]
        let setOutcome = try await identify(set, answers)
        let streamOutcome = try await identify(stream, answers)
        XCTAssertEqual(setOutcome, .notASingleSong)
        XCTAssertEqual(streamOutcome, .notASingleSong)
    }

    // MARK: - YouTube's credit

    func testTrustsACreditForTheSongInTheTitle() async throws {
        let bts = video("BTS (방탄소년단) 'Dynamite' Official MV", channel: "HYBE LABELS")
        let credit = MusicCredit(song: "Dynamite", artist: "BTS (방탄소년단)", album: "BE")
        let outcome = try await identify(bts, credit: credit, ["Dynamite|BTS": [track("BTS", "Dynamite")]])
        XCTAssertEqual(outcome, .song(track("BTS", "Dynamite")))
    }

    func testIgnoresBackgroundMusicCredits() async throws {
        // A tie tutorial credits its backing track, which the video isn't about.
        let tie = video("How to Tie a Tie | Windsor | For Beginners", channel: "defragmenteur")
        let credit = MusicCredit(song: "Strut Funk", artist: "Dougie Wood", album: nil)
        let outcome = try await identify(tie, credit: credit, [
            "Strut Funk|Dougie Wood": [track("Dougie Wood", "Strut Funk")],
            "How to Tie a Tie|": [track("The Lucksmiths", "How to Tie a Tie")]
        ])
        XCTAssertEqual(outcome, .unknown, "Neither the credit nor a namesake song by an unnamed band")
    }

    func testTrustsACreditAcrossScripts() async throws {
        let hindi = video("तुम ही हो  आशिकी 2 पूरा गाना बोल के साथ  | आदित्य रॉय कपूर", channel: "T-Series")
        let credit = MusicCredit(song: "Tum Hi Ho (From \"Aashiqui 2\")", artist: "Arijit Singh", album: nil)
        let outcome = try await identify(hindi, credit: credit, ["Tum Hi Ho|Arijit Singh": [track("Arijit Singh", "Tum Hi Ho")]])
        XCTAssertEqual(outcome, .song(track("Arijit Singh", "Tum Hi Ho")))
    }

    func testAnUnnamedArtistsCreditNeedsListeners() async throws {
        let bebop = video("Cowboy Bebop - Opening - Tank! (HD - 60 fps)", channel: "Anime Guy")
        let credit = MusicCredit(song: "TANK!", artist: "SEATBELTS", album: nil)

        let obscure = try await identify(bebop, credit: credit, ["TANK!|SEATBELTS": [track("Seatbelts", "Tank!", listeners: 300)]])
        XCTAssertNotEqual(obscure, .song(track("Seatbelts", "Tank!", listeners: 300)))

        let known = try await identify(bebop, credit: credit, ["TANK!|SEATBELTS": [track("Seatbelts", "Tank!")]])
        XCTAssertEqual(known, .song(track("Seatbelts", "Tank!")))
    }

    // MARK: - Reading the title

    func testSkipsScrobbledVideoTitles() async throws {
        let newJeans = video("NewJeans - Super Shy (Official MV)", channel: "HYBE LABELS")
        let outcome = try await identify(newJeans, ["Super Shy|NewJeans": [
            track("NewJeans", "Super Shy (Official MV)"),
            track("NewJeans", "Super Shy")
        ]])
        XCTAssertEqual(outcome, .song(track("NewJeans", "Super Shy")))
    }

    func testASongsOwnWordsArentMarkers() async throws {
        let queen = video("Queen - Radio Ga Ga (Official Video)", channel: "Queen Official")
        let outcome = try await identify(queen, ["Radio Ga Ga|Queen": [track("Queen", "Radio Ga Ga")]])
        XCTAssertEqual(outcome, .song(track("Queen", "Radio Ga Ga")))
    }

    func testWithoutAnArtistTheVideoMustNameTheOneFound() async throws {
        let zoo = video("Me at the zoo", channel: "jawed", duration: "0:19")
        let zooOutcome = try await identify(zoo, ["Me at the zoo|": [track("S. Fidelity", "Me at the Zoo")]])
        XCTAssertEqual(zooOutcome, .unknown)

        let conan = video("Radiohead Perform \"Creep\" Live on September 14, 1993 | Late Night with Conan O’Brien", channel: "Conan O'Brien")
        let conanOutcome = try await identify(conan, ["Creep|": [track("Radiohead", "Creep")]])
        XCTAssertEqual(conanOutcome, .song(track("Radiohead", "Creep")))
    }

    // MARK: - Helpers

    func testBareTrack() {
        XCTAssertEqual(TrackMatching.bareTrack("Bloody Mary (TikTok Remix | Speed Up) | Wednesday Dance Scene"), "Bloody Mary")
        XCTAssertEqual(TrackMatching.bareTrack("Get Lucky (feat. Pharrell Williams)"), "Get Lucky (feat. Pharrell Williams)")
        XCTAssertEqual(TrackMatching.bareTrack("Get Lucky (Radio Edit - feat. Pharrell Williams)", dropSubtitles: true), "Get Lucky")
        XCTAssertEqual(TrackMatching.bareTrack("Moonlight Sonata - 3rd Movement (Beethoven)", dropSubtitles: true), "Moonlight Sonata")
    }

    func testGuessKeepsBracketsWithBarsWhole() {
        XCTAssertEqual(
            TrackMatching.guess(title: "Lady Gaga - Bloody Mary (TikTok Remix | Speed Up) | Wednesday Dance Scene", channel: "itsAirLow").artist,
            "Lady Gaga"
        )
    }

    func testLeadArtist() {
        XCTAssertEqual(TrackMatching.leadArtist("Calvin Harris, Rihanna"), "Calvin Harris")
        XCTAssertEqual(TrackMatching.leadArtist("BTS (방탄소년단)"), "BTS")
        XCTAssertEqual(TrackMatching.leadArtist("Tommee Profitt x Skylar Grey"), "Tommee Profitt")
    }

    func testQuoted() {
        XCTAssertEqual(TrackMatching.quoted(in: "TWICE \"What is Love?\" M/V"), "What is Love?")
        XCTAssertEqual(TrackMatching.quoted(in: "YOASOBI「夜に駆ける」 Official Music Video"), "夜に駆ける")
        XCTAssertNil(TrackMatching.quoted(in: "Toto - Africa"))
    }

    func testScripts() {
        XCTAssertTrue(TrackMatching.isMostlyNonLatin("तुम ही हो  आशिकी 2"))
        XCTAssertFalse(TrackMatching.isMostlyNonLatin("Tití Me Preguntó"))
    }

    // MARK: - YouTube's Music section

    func testParsesTheMusicCredit() throws {
        let json = #"""
        { "engagementPanels": [ { "structuredDescriptionContentRenderer": { "items": [
          { "horizontalCardListRenderer": {
              "header": { "richListHeaderRenderer": { "title": { "simpleText": "Music" } } },
              "cards": [ { "videoAttributeViewModel": {
                  "title": "Never Gonna Give You Up (7\" Mix)",
                  "subtitle": "Rick Astley",
                  "secondarySubtitle": { "content": "Whenever You Need Somebody" }
              } } ]
          } },
          { "horizontalCardListRenderer": {
              "header": { "richListHeaderRenderer": { "title": { "simpleText": "Places" } } },
              "cards": [ { "videoAttributeViewModel": { "title": "London", "subtitle": "UK" } } ]
          } }
        ] } } ] }
        """#
        XCTAssertEqual(
            try YouTubeSearch.parseMusicCredit(Data(json.utf8)),
            MusicCredit(song: "Never Gonna Give You Up (7\" Mix)", artist: "Rick Astley", album: "Whenever You Need Somebody")
        )
        XCTAssertNil(try YouTubeSearch.parseMusicCredit(Data(#"{ "contents": {} }"#.utf8)))
    }
}
