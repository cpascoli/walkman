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

        app.segmentedControls["historyFilter"].buttons["Local"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Downloaded video should pass the Local filter")

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

    private func loadVideo() {
        let field = app.textFields["videoInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(videoID)
        app.buttons["playButton"].tap()
    }
}
