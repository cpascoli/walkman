import XCTest

/// A paced walkthrough of the app, used to record the README demo.
///
/// A recording script rather than a test: it drives the app at a readable pace
/// so the walkthrough can be captured for the README.
///
/// The `Walkman` scheme skips it, so it never runs with the normal suite. It
/// runs under the `Walkman-Demo` scheme; `Tools/record-demo.sh` does the whole
/// job, including the capture and the GIF. The similar-tape part needs a
/// Last.fm key (`LASTFM_API_KEY` for the script) and is left out without one.
final class DemoWalkthrough: XCTestCase {

    /// Loaded on the deck at the start.
    private let videoID = "KsE9iXoXB6s"
    /// Searched for, previewed, and made into a tape of similar tracks.
    private let searchQuery = "a-ha take on me"
    private let searchVideoID = "djV11Xbc914"

    func testRecordDemo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        let key = ProcessInfo.processInfo.environment["LASTFM_API_KEY"] ?? ""
        if !key.isEmpty { app.launchEnvironment["LASTFM_API_KEY"] = key }
        app.launch()

        beat(1.5)

        // 1. Paste an ID and load it: the cassette goes in and the hubs turn.
        let field = app.textFields["videoInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(videoID)
        beat(0.6)
        app.buttons["playButton"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 90))
        beat(4.0)

        // 2. A look at the picture, then back to the tape.
        app.buttons["videoToggle"].tap()
        beat(3.0)
        app.buttons["videoToggle"].tap()
        beat(1.5)

        // 3. Search YouTube and open a result.
        app.buttons["tab.Search"].tap()
        beat(0.8)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText(searchQuery + "\n")
        let row = app.buttons["searchResultRow_\(searchVideoID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        beat(2.5)
        row.tap()

        // 4. Preview it.
        XCTAssertTrue(app.staticTexts["previewQuality"].waitForExistence(timeout: 60))
        beat(1.0)
        app.descendants(matching: .any)["searchPreview"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        beat(4.0)

        // 5. Make a tape of similar tracks, and save it.
        if !key.isEmpty {
            app.buttons["similarTapeButton"].tap()
            let progress = app.descendants(matching: .any)["similarTapeProgress"]
            XCTAssertTrue(progress.waitForExistence(timeout: 10))
            XCTAssertTrue(progress.waitForNonExistence(timeout: 120))
            beat(1.5)
            app.swipeUp()
            beat(1.2)
            app.swipeDown()
            beat(1.0)
            app.buttons["saveSimilarTapeButton"].tap()
            beat(1.5)
        }

        // 6. Play from the library: it's back to the deck.
        app.buttons["tab.Library"].tap()
        beat(1.5)
        let tape = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tapeRow_'")).firstMatch
        if tape.waitForExistence(timeout: 3) {
            tape.tap()
            beat(1.5)
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trackRow_'")).element(boundBy: 1).tap()
        } else {
            app.buttons["allRecordingsRow"].tap()
            beat(1.2)
            app.buttons["recordingRow_\(searchVideoID)"].tap()
        }
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 60))
        beat(4.0)

        // 7. Transport keys.
        // First match: the deck's key, not the player's own control.
        app.buttons.matching(NSPredicate(format: "label == 'Pause'")).firstMatch.tap()
        beat(1.2)
        app.buttons.matching(NSPredicate(format: "label == 'Play'")).firstMatch.tap()
        beat(1.5)

        // 8. Settings, and home.
        app.buttons["tab.Settings"].tap()
        beat(2.2)
        app.buttons["tab.Player"].tap()
        beat(2.0)
    }

    /// A readable pause, so the recording isn't a blur of instant transitions.
    private func beat(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
