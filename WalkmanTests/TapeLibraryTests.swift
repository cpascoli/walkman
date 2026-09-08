import XCTest
@testable import Walkman

@MainActor
final class TapeLibraryTests: XCTestCase {

    private var library: TapeLibrary!
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = URL.temporaryDirectory.appendingPathComponent("tapes-\(UUID().uuidString).json")
        library = TapeLibrary(fileURL: fileURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testCreateTrimsAndFallsBackForBlankNames() {
        XCTAssertEqual(library.create(name: "  Road Trip  ").name, "Road Trip")
        XCTAssertEqual(library.create(name: "   ").name, "Untitled Tape")
    }

    func testAddingIsIdempotent() {
        let tape = library.create(name: "Mix")
        library.add("aaa", to: tape)
        library.add("aaa", to: tape)
        library.add("bbb", to: tape)

        XCTAssertEqual(library.tape(withID: tape.id)?.videoIDs, ["aaa", "bbb"])
    }

    func testToggleAddsThenRemoves() {
        let tape = library.create(name: "Mix")

        library.toggle("aaa", on: tape)
        XCTAssertEqual(library.tape(withID: tape.id)?.videoIDs, ["aaa"])

        // Toggle off using the *original* value, as the menu does — the lookup
        // is by id, so a stale copy must still work.
        library.toggle("aaa", on: library.tape(withID: tape.id)!)
        XCTAssertEqual(library.tape(withID: tape.id)?.videoIDs, [])
    }

    func testReorderTracks() {
        let tape = library.create(name: "Mix", videoIDs: ["a", "b", "c"])
        library.moveTracks(in: tape, fromOffsets: IndexSet(integer: 2), toOffset: 0)

        XCTAssertEqual(library.tape(withID: tape.id)?.videoIDs, ["c", "a", "b"])
    }

    func testPurgeRemovesRecordingFromEveryTape() {
        let first = library.create(name: "One", videoIDs: ["a", "b"])
        let second = library.create(name: "Two", videoIDs: ["b", "c"])

        library.purge("b")

        XCTAssertEqual(library.tape(withID: first.id)?.videoIDs, ["a"])
        XCTAssertEqual(library.tape(withID: second.id)?.videoIDs, ["c"])
    }

    func testTapesContaining() {
        let first = library.create(name: "One", videoIDs: ["a"])
        _ = library.create(name: "Two", videoIDs: ["b"])

        XCTAssertEqual(library.tapesContaining("a"), [first.id])
        XCTAssertTrue(library.tapesContaining("zzz").isEmpty)
    }

    func testTapesSurviveAReload() async throws {
        let tape = library.create(name: "Persisted", videoIDs: ["a", "b"])

        // Writes are async; give the detached save a moment to land.
        try await Task.sleep(for: .milliseconds(300))
        let reloaded = TapeLibrary(fileURL: fileURL)

        XCTAssertEqual(reloaded.tape(withID: tape.id)?.name, "Persisted")
        XCTAssertEqual(reloaded.tape(withID: tape.id)?.videoIDs, ["a", "b"])
    }
}
