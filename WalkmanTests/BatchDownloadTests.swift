import XCTest
@testable import Walkman

/// Downloading a whole tape: one at a time, past failures, and only what isn't
/// on the device yet, so starting again carries on where it stopped.
@MainActor
final class BatchDownloadTests: XCTestCase {

    private var directory: URL!
    private var downloads: DownloadManager!

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appendingPathComponent("downloads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("saved.mp4"))
        downloads = DownloadManager(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Records each lookup, and fails it as if offline.
    private final class Resolver {
        var calls: [String] = []
        var running = 0
        var mostAtOnce = 0

        func resolve(_ videoID: String) async throws -> StreamResolver.Source {
            calls.append(videoID)
            running += 1
            mostAtOnce = max(mostAtOnce, running)
            defer { running -= 1 }
            try await Task.sleep(for: .milliseconds(20))
            throw URLError(.notConnectedToInternet)
        }
    }

    private func waitForBatch() async throws {
        let deadline = Date.now.addingTimeInterval(5)
        while !downloads.batch.isEmpty {
            guard Date.now < deadline else { return XCTFail("The batch never finished") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testDownloadsOneAtATimeSkippingSavedAndFailed() async throws {
        let resolver = Resolver()
        downloads.downloadAll(["a", "saved", "b", "a"], resolve: resolver.resolve)
        try await waitForBatch()

        XCTAssertEqual(resolver.calls, ["a", "b"], "Each missing video once, in order")
        XCTAssertEqual(resolver.mostAtOnce, 1)
        guard case .failed = downloads.status(for: "a"), case .failed = downloads.status(for: "b") else {
            return XCTFail("Failures should be marked, and the batch carry on past them")
        }
        XCTAssertEqual(downloads.status(for: "saved"), .downloaded)
    }

    func testStartingAgainRetriesWhatsLeft() async throws {
        let resolver = Resolver()
        downloads.downloadAll(["a", "b"], resolve: resolver.resolve)
        try await waitForBatch()
        downloads.downloadAll(["a", "saved", "b"], resolve: resolver.resolve)
        try await waitForBatch()

        XCTAssertEqual(resolver.calls, ["a", "b", "a", "b"])
    }

    func testCancellingStopsTheRest() async throws {
        let resolver = Resolver()
        downloads.downloadAll(["a", "b", "c"], resolve: resolver.resolve)
        try await Task.sleep(for: .milliseconds(5))
        downloads.cancelBatch()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(resolver.calls, ["a"])
        XCTAssertTrue(downloads.batch.isEmpty)
        XCTAssertEqual(downloads.status(for: "a"), .notDownloaded, "A cancelled video isn't a failed one")
    }
}
