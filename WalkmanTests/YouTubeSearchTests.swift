import XCTest
@testable import Walkman

final class YouTubeSearchTests: XCTestCase {

    /// Trimmed from a real `/youtubei/v1/search` response, keeping its nesting.
    private let firstPage = #"""
    {
      "contents": { "twoColumnSearchResultsRenderer": { "primaryContents": { "sectionListRenderer": {
        "contents": [
          { "itemSectionRenderer": { "contents": [
            { "videoRenderer": {
                "videoId": "suBARTPm1fk",
                "title": { "runs": [ { "text": "Hi Scores" }, { "text": " (Trailer)" } ] },
                "ownerText": { "runs": [ { "text": "Boards of Canada" } ] },
                "lengthText": { "simpleText": "0:53" },
                "viewCountText": { "simpleText": "60,106 views" },
                "shortViewCountText": { "simpleText": "60K views" },
                "publishedTimeText": { "simpleText": "16 hours ago" },
                "detailedMetadataSnippets": [ { "snippetText": { "runs": [ { "text": "Pre-order now" } ] } } ],
                "thumbnail": { "thumbnails": [ { "url": "https://i.ytimg.com/vi/suBARTPm1fk/hq720.jpg", "width": 360 } ] }
            } },
            { "videoRenderer": {
                "videoId": "dQw4w9WgXcQ",
                "title": { "simpleText": "Live now" },
                "longBylineText": { "runs": [ { "text": "Somebody" } ] },
                "descriptionSnippet": { "runs": [ { "text": "Streaming" } ] }
            } },
            { "videoRenderer": { "videoId": "suBARTPm1fk", "title": { "simpleText": "Duplicate" } } },
            { "videoRenderer": { "videoId": "not-a-valid-id", "title": { "simpleText": "Bad" } } },
            { "shelfRenderer": { "title": { "simpleText": "People also watched" } } }
          ] } },
          { "continuationItemRenderer": { "continuationEndpoint": {
              "continuationCommand": { "token": "NEXT_PAGE", "request": "CONTINUATION_REQUEST_TYPE_SEARCH" }
          } } }
        ]
      } } } }
    }
    """#

    func testParsesVideoRenderersWherever() throws {
        let page = try YouTubeSearch.parse(Data(firstPage.utf8))

        XCTAssertEqual(page.results.map(\.id), ["suBARTPm1fk", "dQw4w9WgXcQ"])
        XCTAssertEqual(page.continuation, "NEXT_PAGE")

        let first = page.results[0]
        XCTAssertEqual(first.title, "Hi Scores (Trailer)")
        XCTAssertEqual(first.channel, "Boards of Canada")
        XCTAssertEqual(first.snippet, "Pre-order now")
        XCTAssertEqual(first.duration, "0:53")
        XCTAssertEqual(first.viewCount, "60K views")
        XCTAssertEqual(first.thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/suBARTPm1fk/hq720.jpg")
        XCTAssertEqual(first.metadataLine, "Boards of Canada · 0:53 · 60K views · 16 hours ago")
    }

    func testFallsBackForMissingFields() throws {
        let second = try YouTubeSearch.parse(Data(firstPage.utf8)).results[1]

        XCTAssertEqual(second.title, "Live now")
        XCTAssertEqual(second.channel, "Somebody")
        XCTAssertEqual(second.snippet, "Streaming")
        XCTAssertEqual(second.duration, "")
        XCTAssertEqual(second.thumbnailURL, HistoryEntry.defaultThumbnailURL(for: "dQw4w9WgXcQ"))
    }

    func testContinuationPageShape() throws {
        let json = #"""
        { "onResponseReceivedCommands": [ { "appendContinuationItemsAction": { "continuationItems": [
            { "itemSectionRenderer": { "contents": [
              { "videoRenderer": { "videoId": "aaaaaaaaaaa", "title": { "simpleText": "More" } } }
            ] } }
        ] } } ] }
        """#
        let page = try YouTubeSearch.parse(Data(json.utf8))

        XCTAssertEqual(page.results.map(\.id), ["aaaaaaaaaaa"])
        XCTAssertNil(page.continuation)
    }
}
