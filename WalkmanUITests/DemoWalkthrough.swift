import XCTest

/// A paced walkthrough of the app, used to record the README demo.
///
/// A recording script rather than a test: it drives the app at a readable pace
/// so the walkthrough can be captured for the README.
///
/// The `Walkman` scheme skips it, so it never runs with the normal suite. It
/// runs under the `Walkman-Demo` scheme; `Tools/record-demo.sh` does the whole
/// job, including the capture and the GIF. The similar-tape part needs a
/// Last.fm key — `LASTFM_API_KEY` for the script, or one saved in the
/// simulator's Settings; without one the tape is just the song searched for.
///
/// Each section starts with a title card, and the simulator records landscape
/// sideways, so the sections and each turn of the device are logged with the
/// time (`DEMO-MARK`), for the script to lay the GIF out by.
final class DemoWalkthrough: XCTestCase {

    /// Searched for, previewed, and made into a tape of tracks like it.
    private let searchQuery = "Music Is Math Boards of Canada"
    /// The band's own upload.
    private let searchVideoID = "YSi78g2CXCM"

    func testRecordDemo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        let key = ProcessInfo.processInfo.environment["LASTFM_API_KEY"] ?? ""
        if !key.isEmpty { app.launchEnvironment["LASTFM_API_KEY"] = key }
        section("Walkman", "A personal cassette deck for YouTube: find music, wind it onto tapes, and take it with you.")
        app.launch()

        // The deck as it opens, long enough to register between the cards.
        beat(4.0)

        // 1. Search YouTube for a song and open it: the preview plays as soon
        // as it's cued.
        section("Search YouTube", "Find any song and preview it straight away. Here, Boards of Canada's “Music Is Math”.")
        app.buttons["tab.Search"].tap()
        beat(0.8)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText(searchQuery + "\n")
        let row = app.buttons["searchResultRow_\(searchVideoID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        beat(2.0)
        row.tap()
        XCTAssertTrue(app.staticTexts["previewQuality"].waitForExistence(timeout: 60))
        beat(4.0)

        // 2. A tape of similar tracks, filling in as each is found on YouTube.
        section("A tape of similar tracks", "Last.fm names the song and suggests twenty like it, each found on YouTube. Look it over, then save it.")
        app.buttons["similarTapeButton"].tap()
        let progress = app.descendants(matching: .any)["similarTapeProgress"]
        let hasKey = progress.waitForExistence(timeout: 5)
        if hasKey {
            XCTAssertTrue(progress.waitForNonExistence(timeout: 120))
            beat(1.5)
            app.swipeUp()
            beat(1.2)
            app.swipeDown()
            beat(1.0)
            app.buttons["saveSimilarTapeButton"].tap()
            beat(1.5)
        } else {
            // No key: a tape of just this song, so the rest still has one to show.
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["newTapeFromSearchButton"].tap()
            let name = app.alerts.textFields.firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Music Is Math")
            app.alerts.buttons["Create"].tap()
            beat(1.0)
        }

        // 3. Open the tape and download it all to the device, one at a time.
        section("Download a whole tape", "Every track is saved to the phone, one at a time, for listening offline. It carries on while you do other things.")
        app.buttons["tab.Library"].tap()
        beat(1.2)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tapeRow_'")).firstMatch.tap()
        beat(2.0)
        app.buttons["tapeMenu"].tap()
        beat(1.0)
        app.buttons["downloadTapeButton"].tap()
        let status = app.descendants(matching: .any)["tapeDownloadStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        // Watch the first come down, then leave the rest going. A tape of one
        // is done at that point, and the progress goes.
        let deadline = Date.now.addingTimeInterval(90)
        while status.exists, !status.label.contains("· 1 of"), Date.now < deadline {
            beat(0.5)
        }
        beat(2.0)

        // 4. Play from the tape: back to the deck, the cassette in and turning.
        section("Play it on the deck", "The cassette goes in, the reels turn, and the tape winds from one spool to the other as it plays.")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trackRow_'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 60))
        beat(4.0)

        // 5. On its side: the cassette fills the screen. Holding the gap to
        // its right winds on.
        section("Turn it on its side", "The cassette fills the screen. Tap to play or pause, double-tap to skip, and hold either side to wind.")
        turn(to: .landscapeLeft)
        beat(2.5)
        let deck = app.descendants(matching: .any)["deckGestures"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5))
        deck.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 40, dy: 0))
            .press(forDuration: 2.0)
        beat(1.5)
        turn(to: .portrait)
        beat(1.5)

        // 6. The picture instead, and on its side, full screen.
        section("Or watch the video", "Switch the deck to the picture, and on its side it plays full screen.")
        app.buttons["videoToggle"].tap()
        beat(2.0)
        turn(to: .landscapeLeft)
        beat(3.5)
        turn(to: .portrait)
        beat(1.0)
        app.buttons["videoToggle"].tap()
        beat(2.0)
    }

    /// Turns the device, marking the time for the recording script.
    private func turn(to orientation: UIDeviceOrientation) {
        let name = orientation == .portrait ? "portrait" : "landscape"
        NSLog("%@", "DEMO-MARK \(name) \(Date.now.timeIntervalSince1970)")
        XCUIDevice.shared.orientation = orientation
    }

    /// Marks the start of a section, for a title card in the GIF.
    private func section(_ title: String, _ copy: String) {
        NSLog("%@", "DEMO-MARK section \(Date.now.timeIntervalSince1970) \(title) | \(copy)")
    }

    /// A readable pause, so the recording isn't a blur of instant transitions.
    private func beat(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
