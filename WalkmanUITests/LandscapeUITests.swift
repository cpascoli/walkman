import XCTest

/// Turned on its side, the deck shows just the tape window, full screen, and
/// comes back whole when it's turned upright again.
final class LandscapeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    func testLandscapeShowsOnlyTheTapeWindow() {
        XCTAssertTrue(app.textFields["videoInput"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tab.Player"].exists)

        XCUIDevice.shared.orientation = .landscapeLeft

        let empty = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "No tape loaded")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "The empty bay should fill the screen")
        XCTAssertTrue(app.buttons["tab.Player"].waitForNonExistence(timeout: 5), "The tab bar should make way for the tape")
        XCTAssertFalse(app.textFields["videoInput"].exists, "The rest of the deck should fall away")
        XCTAssertFalse(app.buttons["videoToggle"].exists)

        XCUIDevice.shared.orientation = .portrait

        XCTAssertTrue(app.textFields["videoInput"].waitForExistence(timeout: 5), "Upright, the whole deck should come back")
        XCTAssertTrue(app.buttons["tab.Player"].exists)
    }

    /// Other tabs keep their usual layout on their side.
    func testOtherTabsStayAsTheyAreInLandscape() {
        app.buttons["tab.Library"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft

        XCTAssertTrue(app.buttons["allRecordingsRow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab.Library"].exists)
    }

    /// On its side the cassette is the controls. Talks to YouTube, to load a tape.
    func testTheCassetteIsTheControls() {
        let field = app.textFields["videoInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("jNQXAC9IVRw")
        app.buttons["playButton"].tap()
        XCTAssertTrue(app.buttons["downloadButton"].waitForExistence(timeout: 90), "The tape should load")

        XCUIDevice.shared.orientation = .landscapeLeft
        let deck = app.descendants(matching: .any)["deckGestures"]
        XCTAssertTrue(deck.waitForExistence(timeout: 5))

        // Under way first: a tap while it's still cueing starts it instead.
        wait(for: deck, valueBeginsWith: "Playing", timeout: 30)

        // A tap pauses, so the counter holds still for what follows.
        deck.tap()
        wait(for: deck, valueBeginsWith: "Paused")
        let start = seconds(deck)

        // Holding the gap to the right winds on, a few seconds a step.
        deck.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 30, dy: 0))
            .press(forDuration: 1.5)
        let wound = seconds(deck)
        XCTAssertGreaterThanOrEqual(wound, start + 8, "Holding the right gap should wind on")

        // And to the left, back.
        deck.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: -30, dy: 0))
            .press(forDuration: 1.5)
        XCTAssertLessThanOrEqual(seconds(deck), wound - 8, "Holding the left gap should wind back")

        // Three taps: back to the start.
        deck.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        wait(for: deck, valueBeginsWith: "Paused, 0:00")

        deck.tap()
        wait(for: deck, valueBeginsWith: "Playing")
    }

    private func wait(
        for element: XCUIElement,
        valueBeginsWith prefix: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "value BEGINSWITH %@", prefix)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout)
        XCTAssertEqual(result, .completed, "Expected \(prefix)…, got \(element.value ?? "nothing")", file: file, line: line)
    }

    /// The counter reading in the deck's value, e.g. "Paused, 0:12".
    private func seconds(_ deck: XCUIElement) -> Int {
        // Let the last wind step land.
        Thread.sleep(forTimeInterval: 0.5)
        let reading = (deck.value as? String)?.split(separator: " ").last ?? ""
        let parts = reading.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }
}
