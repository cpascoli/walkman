import XCTest
@testable import YouTubePlayer

final class YouTubeVideoIDTests: XCTestCase {

    private let id = "dQw4w9WgXcQ"

    func testParsesBareID() {
        XCTAssertEqual(YouTubeVideoID.parse(id), id)
        XCTAssertEqual(YouTubeVideoID.parse("  \(id)\n"), id, "Pasted IDs often carry whitespace")
    }

    func testParsesURLShapes() {
        let urls = [
            "https://www.youtube.com/watch?v=\(id)",
            "https://www.youtube.com/watch?v=\(id)&t=42s",
            "https://youtu.be/\(id)",
            "https://youtu.be/\(id)?t=42",
            "https://www.youtube.com/shorts/\(id)",
            "https://www.youtube.com/embed/\(id)",
            "https://www.youtube.com/live/\(id)",
            "https://www.youtube-nocookie.com/embed/\(id)",
            "youtube.com/watch?v=\(id)",
            "m.youtube.com/watch?v=\(id)"
        ]

        for url in urls {
            XCTAssertEqual(YouTubeVideoID.parse(url), id, "Failed to parse \(url)")
        }
    }

    func testRejectsInvalidInput() {
        let bad = ["", "   ", "https://vimeo.com/12345", "https://www.youtube.com/", "!!nope!!", "tooshort"]

        for input in bad {
            XCTAssertNil(YouTubeVideoID.parse(input), "Should reject \(input)")
        }
    }

    func testRejectsWrongLengthIDs() {
        XCTAssertFalse(YouTubeVideoID.isValid("abc"))
        XCTAssertFalse(YouTubeVideoID.isValid("dQw4w9WgXcQextra"))
        XCTAssertTrue(YouTubeVideoID.isValid("dQw4w9WgXcQ"))
    }
}
