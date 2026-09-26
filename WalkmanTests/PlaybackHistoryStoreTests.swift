import XCTest
@testable import Walkman

@MainActor
final class PlaybackHistoryStoreTests: XCTestCase {

    private var store: PlaybackHistoryStore!
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = URL.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).json")
        store = PlaybackHistoryStore(fileURL: fileURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testAddFilesWithoutCountingAPlay() {
        store.add(videoID: "aaaaaaaaaaa", title: "Found It")

        XCTAssertEqual(store.entries.first?.id, "aaaaaaaaaaa")
        XCTAssertEqual(store.entries.first?.title, "Found It")
        XCTAssertEqual(store.entries.first?.playCount, 0)
        XCTAssertTrue(store.contains("aaaaaaaaaaa"))
    }

    func testAddLeavesAnExistingEntryAlone() {
        store.recordPlay(videoID: "aaaaaaaaaaa", title: "Played")
        store.recordPlay(videoID: "bbbbbbbbbbb", title: "Newer")

        store.add(videoID: "aaaaaaaaaaa", title: "From Search")

        XCTAssertEqual(store.entries.map(\.id), ["bbbbbbbbbbb", "aaaaaaaaaaa"])
        XCTAssertEqual(store.entries[1].title, "Played")
        XCTAssertEqual(store.entries[1].playCount, 1)
    }

    func testAddLendsATitleToAnUntitledEntry() {
        store.recordPlay(videoID: "aaaaaaaaaaa")

        store.add(videoID: "aaaaaaaaaaa", title: "Found It")

        XCTAssertEqual(store.entries.first?.title, "Found It")
    }

    func testFirstPlayAfterFilingCountsOnce() {
        store.add(videoID: "aaaaaaaaaaa", title: "Found It")
        store.recordPlay(videoID: "aaaaaaaaaaa")

        XCTAssertEqual(store.entries.first?.playCount, 1)
    }
}
