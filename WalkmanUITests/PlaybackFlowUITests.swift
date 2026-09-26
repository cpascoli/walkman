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
        app.buttons["tab.Library"].tap()

        // The downloaded recording should be filed under Taped.
        app.buttons["tapedRow"].tap()

        let row = app.buttons["recordingRow_\(videoID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Taped recording should be listed under Taped")

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

    /// Create a tape, put a recording on it, and play from the tape.
    func testCreateTapeAddRecordingAndPlayFromIt() {
        load(videoID)
        XCTAssertTrue(
            app.descendants(matching: .any)["downloadButton"].waitForExistence(timeout: 90),
            "Seed recording should resolve"
        )

        app.buttons["tab.Library"].tap()

        // Create a tape, accepting the pre-filled name.
        app.buttons["newTapeButton"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Create"].tap()

        let tapeRow = app.buttons["tapeRow_Tape 1"]
        XCTAssertTrue(tapeRow.waitForExistence(timeout: 5), "New tape should appear on the shelf")

        // Put the recording on it from the catalogue.
        app.buttons["allRecordingsRow"].tap()
        let recording = app.buttons["recordingRow_\(videoID)"]
        XCTAssertTrue(recording.waitForExistence(timeout: 10))
        recording.press(forDuration: 1.2)

        let addToTape = app.buttons["Add to Tape"]
        XCTAssertTrue(addToTape.waitForExistence(timeout: 5), "Context menu should offer Add to Tape")
        addToTape.tap()

        let tapeChoice = app.buttons["Tape 1"]
        XCTAssertTrue(tapeChoice.waitForExistence(timeout: 5))
        tapeChoice.tap()

        // Back to the shelf, open the tape, and play its track.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(tapeRow.waitForExistence(timeout: 5))
        tapeRow.tap()

        let track = app.buttons["trackRow_\(videoID)"]
        XCTAssertTrue(track.waitForExistence(timeout: 5), "The recording should be on the tape")
        track.tap()

        // The deck should now report that it is playing from that tape.
        let readout = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Tape 1")
        ).firstMatch
        XCTAssertTrue(readout.waitForExistence(timeout: 30), "The deck should show the loaded tape")
    }

    /// A recording with a local copy must play through AVPlayer even when the
    /// user has picked the embedded player, because the web view can neither
    /// reach the file nor keep playing in the background.
    func testDownloadedRecordingUsesTheNativePlayerUnderTheEmbeddedSetting() {
        loadVideo()

        let downloadButton = app.descendants(matching: .any)["downloadButton"]
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 90))
        downloadButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["downloadedBadge"].waitForExistence(timeout: 180),
            "Recording should be stored on device"
        )

        // Switch the preference to the embedded player.
        app.buttons["tab.Settings"].tap()
        let embedded = app.segmentedControls.buttons["Embedded"]
        XCTAssertTrue(embedded.waitForExistence(timeout: 5))
        embedded.tap()
        app.buttons["tab.Player"].tap()

        // It should still be the native player on screen, playing the local file.
        XCTAssertTrue(
            app.descendants(matching: .any)["localPlaybackBadge"].waitForExistence(timeout: 30),
            "A downloaded recording should stay on the native player"
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
