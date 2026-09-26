import XCTest

/// The tab bar behaves like the system one: switching tabs keeps each tab
/// where you left it, and tapping the tab you're on goes back to its top.
final class TabBarUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()
    }

    func testTappingTheCurrentTabGoesBackToItsFirstScreen() {
        app.buttons["tab.Library"].tap()
        app.buttons["allRecordingsRow"].tap()
        XCTAssertTrue(app.navigationBars["All Recordings"].waitForExistence(timeout: 5))

        // Away and back: still where it was left.
        app.buttons["tab.Player"].tap()
        app.buttons["tab.Library"].tap()
        XCTAssertTrue(app.navigationBars["All Recordings"].waitForExistence(timeout: 5), "Switching tabs should keep the tab's place")

        // Tapped again while showing: back to the top.
        app.buttons["tab.Library"].tap()
        XCTAssertTrue(app.navigationBars["Tape Library"].waitForExistence(timeout: 5), "Tapping the current tab should go back to its first screen")
        XCTAssertTrue(app.buttons["allRecordingsRow"].exists)
    }

    /// Going back to the top of Search keeps the results.
    func testSearchGoesBackToItsResults() {
        app.buttons["tab.Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("me at the zoo jawed\n")

        let row = app.buttons["searchResultRow_jNQXAC9IVRw"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["searchPreview"].waitForExistence(timeout: 10))

        app.buttons["tab.Search"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The results should still be there")
        XCTAssertFalse(app.descendants(matching: .any)["searchPreview"].exists, "The preview should be closed")
    }
}
