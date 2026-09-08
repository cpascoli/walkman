import XCTest
@testable import YouTubePlayer

@MainActor
final class PlayQueueTests: XCTestCase {

    private func entries(_ ids: [String]) -> [HistoryEntry] {
        ids.map { HistoryEntry(id: $0, title: $0) }
    }

    func testRebuildRotatesSoChosenTapeLeads() {
        let queue = PlayQueue()
        queue.rebuild(from: entries(["a", "b", "c", "d"]), startingAt: "c")

        XCTAssertEqual(queue.ids, ["c", "d", "a", "b"])
        XCTAssertEqual(queue.current, "c")
    }

    func testRebuildLeadsWithAnUnknownTape() {
        let queue = PlayQueue()
        queue.rebuild(from: entries(["a", "b"]), startingAt: "new")

        XCTAssertEqual(queue.ids, ["new", "a", "b"])
        XCTAssertEqual(queue.current, "new")
    }

    func testAdvanceWrapsAroundTheEnd() {
        let queue = PlayQueue()
        queue.rebuild(from: entries(["a", "b", "c"]), startingAt: "a")

        XCTAssertEqual(queue.advance(), "b")
        XCTAssertEqual(queue.advance(), "c")
        XCTAssertEqual(queue.advance(), "a", "The queue should loop rather than stop")
    }

    func testAdvanceOnSingleTapeReturnsItself() {
        let queue = PlayQueue()
        queue.rebuild(from: entries(["only"]), startingAt: "only")

        XCTAssertEqual(queue.advance(), "only")
    }

    func testAdvanceOnEmptyQueueIsNil() {
        XCTAssertNil(PlayQueue().advance())
    }
}
