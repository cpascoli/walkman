import XCTest

/// Search, ask for a tape of similar tracks, prune it, and save it. Talks to
/// Last.fm and YouTube, so it needs network access and a Last.fm key, passed
/// as `TEST_RUNNER_LASTFM_API_KEY` to xcodebuild. Skipped without one.
final class SimilarTapeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let key = ProcessInfo.processInfo.environment["LASTFM_API_KEY"], !key.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_LASTFM_API_KEY to run this test")
        }
        app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launchEnvironment["LASTFM_API_KEY"] = key
        app.launch()
    }

    func testMakeASimilarTapeFromASearchResult() {
        app.buttons["tab.Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("rick astley never gonna give you up\n")

        let row = app.buttons["searchResultRow_dQw4w9WgXcQ"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()

        let makeTape = app.buttons["similarTapeButton"]
        XCTAssertTrue(makeTape.waitForExistence(timeout: 10))
        makeTape.tap()

        // Fills in as YouTube searches land; done when the progress row goes.
        let progress = app.descendants(matching: .any)["similarTapeProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.waitForNonExistence(timeout: 120), "The draft should finish")
        XCTAssertFalse(app.descendants(matching: .any)["similarTapeError"].exists)

        let drafted = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'draftTrack_'"))
        // The list only exposes rows on screen, so count from the header.
        let count = Int(app.staticTexts["draftTrackCount"].label) ?? 0
        XCTAssertGreaterThanOrEqual(count, 11, "The original plus most of Last.fm's 20")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "draft"; shot.lifetime = .keepAlways; add(shot)

        // Drop the second track.
        let dropped = drafted.element(boundBy: 1)
        let droppedID = dropped.identifier
        dropped.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons[droppedID].waitForNonExistence(timeout: 5))

        let name = app.textFields["similarTapeName"]
        XCTAssertEqual(name.value as? String, "Like Never Gonna Give You Up", "Named after the song Last.fm found")

        app.buttons["saveSimilarTapeButton"].tap()

        // Back on the preview, whose tape list now shows the new tape with this track on it.
        let saved = app.buttons["tapeToggle_Like Never Gonna Give You Up"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(saved.label.contains("\(count - 1)"), "Saved with \(count - 1) tracks: \(saved.label)")
    }

    /// A tape of one song, extended with twenty more like it.
    func testAddMoreLikeTheLastTrack() {
        app.buttons["tab.Library"].tap()
        app.buttons["newTapeButton"].tap()
        let nameField = app.textFields["tapeNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.clearAndType("Mix")
        app.buttons["Create"].tap()

        app.buttons["tab.Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("rick astley never gonna give you up\n")
        let row = app.buttons["searchResultRow_dQw4w9WgXcQ"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        let toggle = app.buttons["tapeToggle_Mix"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.tap()

        app.buttons["tab.Library"].tap()
        app.buttons["tapeRow_Mix"].tap()
        let extend = app.buttons["extendTapeButton"]
        XCTAssertTrue(extend.waitForExistence(timeout: 10))
        extend.tap()

        let progress = app.descendants(matching: .any)["extendTapeProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertTrue(progress.waitForNonExistence(timeout: 120), "Extending should finish")
        XCTAssertFalse(app.descendants(matching: .any)["extendTapeError"].exists)

        let result = app.staticTexts["extendTapeResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.hasPrefix("Added"), result.label)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "extended"; shot.lifetime = .keepAlways; add(shot)

        // The original stays first, with the new tracks after it.
        let tracks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trackRow_'"))
        XCTAssertEqual(tracks.firstMatch.identifier, "trackRow_dQw4w9WgXcQ")
        app.buttons["tab.Library"].tap()
        let tapeRow = app.buttons["tapeRow_Mix"]
        XCTAssertTrue(tapeRow.waitForExistence(timeout: 5))
        XCTAssertFalse(tapeRow.label.contains("1 track"), "The tape should have grown: \(tapeRow.label)")
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
