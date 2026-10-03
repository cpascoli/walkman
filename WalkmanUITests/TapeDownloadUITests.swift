import XCTest

/// Download a whole tape from its menu. Talks to YouTube, so it needs network
/// access, like the playback flow.
final class TapeDownloadUITests: XCTestCase {

    /// "Me at the zoo" — 19 seconds, so quick to save.
    private let videoID = "jNQXAC9IVRw"

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()
    }

    func testDownloadAllSavesTheTapeAndCarriesOnAway() {
        // A tape with the video on it, filed from search without playing it.
        app.buttons["tab.Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("me at the zoo jawed\n")
        let row = app.buttons["searchResultRow_\(videoID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        app.buttons["newTapeFromSearchButton"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.clearAndType("Zoo")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.buttons["tapeToggle_Zoo"].waitForExistence(timeout: 5))

        app.buttons["tab.Library"].tap()
        app.buttons["tapeRow_Zoo"].tap()
        let track = app.buttons["trackRow_\(videoID)"]
        XCTAssertTrue(track.waitForExistence(timeout: 5))

        app.buttons["tapeMenu"].tap()
        let downloadAll = app.buttons["Download All"]
        XCTAssertTrue(downloadAll.waitForExistence(timeout: 5))
        downloadAll.tap()

        let status = app.descendants(matching: .any)["tapeDownloadStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Progress should show while it downloads")

        // Leave the tape while it works: it should carry on regardless.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["tab.Player"].tap()
        app.buttons["tab.Library"].tap()

        let onDevice = app.buttons["tapedRow"]
        XCTAssertTrue(onDevice.waitForExistence(timeout: 5))
        let saved = NSPredicate(format: "NOT (label CONTAINS 'Zero KB')")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: onDevice)], timeout: 180),
            .completed,
            "The download should finish away from the tape: \(onDevice.label)"
        )

        app.buttons["tapeRow_Zoo"].tap()
        XCTAssertTrue(status.waitForNonExistence(timeout: 30), "Progress should go once it's done")
        app.buttons["tapeMenu"].tap()
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Download All"].exists, "Nothing left to download")
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
