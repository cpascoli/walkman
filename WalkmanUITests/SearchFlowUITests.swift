import XCTest

/// Search YouTube, open a result, and file it onto a new tape. Talks to
/// YouTube, so like the playback flow it needs network access.
final class SearchFlowUITests: XCTestCase {

    /// "Me at the zoo" — a stable first hit for its own title.
    private let videoID = "jNQXAC9IVRw"

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()
    }

    func testSearchThenFileOntoANewTape() {
        app.buttons["searchButton"].tap()

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("me at the zoo jawed\n")

        let row = app.buttons["searchResultRow_\(videoID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The search should list the video")
        row.tap()

        XCTAssertTrue(app.descendants(matching: .any)["searchPreview"].waitForExistence(timeout: 10))
        // The preview streams the video itself; the quality badge appears once it has resolved.
        XCTAssertTrue(
            app.descendants(matching: .any)["previewQuality"].waitForExistence(timeout: 60),
            "The preview should resolve a stream"
        )

        // Putting it on a new tape files it in All Recordings too.
        app.buttons["newTapeFromSearchButton"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.clearAndType("Zoo")
        app.alerts.buttons["Create"].tap()

        XCTAssertTrue(app.buttons["tapeToggle_Zoo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["addToRecordingsButton"].isEnabled, "Filing onto a tape should file the recording")

        // Back out to the deck and check the library.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // The search field is still active, and its Cancel stands in for Done.
        app.navigationBars.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
        app.buttons["libraryButton"].tap()

        app.buttons["tapeRow_Zoo"].tap()
        XCTAssertTrue(app.buttons["trackRow_\(videoID)"].waitForExistence(timeout: 5), "The tape should hold the result")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["allRecordingsRow"].tap()
        XCTAssertTrue(app.buttons["recordingRow_\(videoID)"].waitForExistence(timeout: 5))
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
