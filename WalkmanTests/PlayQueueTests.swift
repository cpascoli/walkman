import XCTest
@testable import Walkman

@MainActor
final class PlayQueueTests: XCTestCase {


    func testRebuildRotatesSoChosenTapeLeads() {
        let queue = PlayQueue()
        queue.rebuild(ids: ["a", "b", "c", "d"], startingAt: "c", sourceName: "Mix")

        XCTAssertEqual(queue.ids, ["c", "d", "a", "b"])
        XCTAssertEqual(queue.current, "c")
    }

    func testRebuildLeadsWithAnUnknownTape() {
        let queue = PlayQueue()
        queue.rebuild(ids: ["a", "b"], startingAt: "new", sourceName: "Mix")

        XCTAssertEqual(queue.ids, ["new", "a", "b"])
        XCTAssertEqual(queue.current, "new")
    }

    func testAdvanceWrapsAroundTheEnd() {
        let queue = PlayQueue()
        queue.rebuild(ids: ["a", "b", "c"], startingAt: "a", sourceName: "Mix")

        XCTAssertEqual(queue.advance(), "b")
        XCTAssertEqual(queue.advance(), "c")
        XCTAssertEqual(queue.advance(), "a", "The queue should loop rather than stop")
    }

    func testAdvanceOnSingleTapeReturnsItself() {
        let queue = PlayQueue()
        queue.rebuild(ids: ["only"], startingAt: "only", sourceName: "Mix")

        XCTAssertEqual(queue.advance(), "only")
    }

    func testAdvanceOnEmptyQueueIsNil() {
        XCTAssertNil(PlayQueue().advance())
        XCTAssertNil(PlayQueue().previous())
    }

    func testPreviousWrapsBackwards() {
        let queue = PlayQueue()
        queue.rebuild(ids: ["a", "b", "c"], startingAt: "a", sourceName: "Mix")

        XCTAssertEqual(queue.previous(), "c", "Stepping back from the first track wraps to the last")
        XCTAssertEqual(queue.previous(), "b")
    }

    func testPositionTracksTheRunningOrder() {
        let queue = PlayQueue()
        queue.rebuild(ids: ["a", "b", "c"], startingAt: "b", sourceName: "Mix")

        XCTAssertEqual(queue.ids, ["b", "c", "a"])
        XCTAssertEqual(queue.position, 1)
        _ = queue.advance()
        XCTAssertEqual(queue.position, 2)
        XCTAssertEqual(queue.sourceName, "Mix")
    }
}
