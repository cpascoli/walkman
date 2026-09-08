import XCTest

/// End-to-end smoke test over the native engine: stream a video, download it,
/// find it in history, and confirm it plays back from the local file.
///
/// This test talks to YouTube, so it needs network access and is inherently
/// slower and more fragile than a unit test — it exists to catch breakage in
/// the extraction pipeline, which is the part most likely to rot.
final class PlaybackFlowUITests: XCTestCase {

    /// "Me at the zoo" — 19 seconds, and the most stable video on YouTube.
    private let videoID = "jNQXAC9IVRw"

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()
    }

    func testStreamThenDownloadThenPlayFromHistory() {
        loadVideo()

        // 1. Streaming resolved and the download control is offered.
        let downloadButton = app.buttons["downloadButton"]
        XCTAssertTrue(
            downloadButton.waitForExistence(timeout: 90),
            "Stream extraction should finish and offer a download"
        )

        // 2. Download to device and wait for the export to complete.
        downloadButton.tap()
        let downloadedBadge = app.buttons["downloadedBadge"]
        XCTAssertTrue(
            downloadedBadge.waitForExistence(timeout: 180),
            "Download should complete and show the saved badge"
        )

        // 3. The video shows up in history, and survives the Local filter.
        app.buttons["historyButton"].tap()

        let row = app.buttons["historyRow_\(videoID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Played video should be in history")

        app.segmentedControls["historyFilter"].buttons["Taped"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Taped video should pass the Taped filter")

        // 4. Selecting it plays the local file rather than streaming.
        row.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["localPlaybackBadge"].waitForExistence(timeout: 30),
            "Selecting a downloaded video should play the on-device file"
        )
    }

    func testInvalidInputIsRejected() {
        let field = app.textFields["videoInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("!!nope!!")
        app.buttons["playButton"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["errorMessage"].waitForExistence(timeout: 5),
            "Garbage input should surface a validation message"
        )
    }

    /// Plays a 19-second tape with a long one queued behind it, then waits out
    /// the tape plus the 2-second gap and checks the deck rolled on by itself.
    func testContinuousPlayAdvancesToTheNextTape() {
        // Seed the library so there is something to advance *to*.
        load("dQw4w9WgXcQ")
        XCTAssertTrue(
            app.descendants(matching: .any)["downloadButton"].waitForExistence(timeout: 90),
            "The queued tape should resolve"
        )

        // Now play the short one; the queue leads with it, followed by the long one.
        clearInput()
        load(videoID)

        // Prove the short tape is actually the one playing before waiting on the
        // hand-off, otherwise a failed switch would make the next assertion pass
        // for the wrong reason.
        let shortTapeTitle = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Me at the zoo")
        ).firstMatch
        XCTAssertTrue(shortTapeTitle.waitForExistence(timeout: 90), "The short tape should be playing")

        // 19s of tape + a 2s gap + metadata for the next one.
        let nextTapeTitle = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Never Gonna Give You Up")
        ).firstMatch

        XCTAssertTrue(
            nextTapeTitle.waitForExistence(timeout: 120),
            "Playback should roll on to the next tape in the library on its own"
        )
    }

    private func clearInput() {
        let field = app.textFields["videoInput"]
        field.tap()
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
    }

    private func load(_ id: String) {
        let field = app.textFields["videoInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(id)
        app.buttons["playButton"].tap()
    }

    private func loadVideo() {
        load(videoID)
    }
}
