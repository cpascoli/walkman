import XCTest

/// A paced walkthrough of the app, used to record the README demo.
///
/// A recording script rather than a test: it drives the app at a readable pace
/// so the walkthrough can be captured for the README.
///
/// The `Walkman` scheme skips it, so it never runs with the normal suite. It
/// runs under the `Walkman-Demo` scheme; `Tools/record-demo.sh` does the whole
/// job, including the capture and the GIF.
final class DemoWalkthrough: XCTestCase {

    private let videoID = "KsE9iXoXB6s"

    func testRecordDemo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()

        beat(1.5)

        // 1. Paste an ID and load it.
        let field = app.textFields["videoInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(videoID)
        beat(0.6)
        app.buttons["playButton"].tap()

        // 2. Let it resolve and play.
        let rec = app.descendants(matching: .any)["downloadButton"]
        XCTAssertTrue(rec.waitForExistence(timeout: 90))
        beat(2.5)

        // 3. Record it to the device.
        rec.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["downloadedBadge"].waitForExistence(timeout: 300)
        )
        beat(1.8)

        // 4. Make a tape.
        app.buttons["libraryButton"].tap()
        beat(1.2)
        app.buttons["newTapeButton"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let nameField = alert.textFields.firstMatch
        nameField.tap()
        let prefilled = (nameField.value as? String) ?? ""
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: prefilled.count))
        nameField.typeText("Road Trip")
        beat(0.6)
        alert.buttons["Create"].tap()
        beat(1.2)

        // 5. Put the recording on it.
        app.buttons["allRecordingsRow"].tap()
        beat(1.0)
        let recording = app.buttons["recordingRow_\(videoID)"]
        XCTAssertTrue(recording.waitForExistence(timeout: 10))
        recording.press(forDuration: 1.1)
        beat(0.8)
        app.buttons["Add to Tape"].tap()
        beat(0.8)
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Road Trip'")).firstMatch.tap()
        beat(1.0)

        // 6. Play it off the tape.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        beat(0.8)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tapeRow_'")).firstMatch.tap()
        beat(1.0)
        app.buttons["trackRow_\(videoID)"].tap()
        beat(3.0)

        // 7. Transport keys.
        app.buttons.matching(NSPredicate(format: "label == 'Pause'")).firstMatch.tap()
        beat(1.2)
        app.buttons.matching(NSPredicate(format: "label == 'Play'")).firstMatch.tap()
        beat(1.5)

        // 8. Settings.
        app.buttons["settingsButton"].tap()
        beat(2.2)
        app.buttons["Done"].tap()
        beat(1.5)
    }

    /// A readable pause, so the recording isn't a blur of instant transitions.
    private func beat(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
