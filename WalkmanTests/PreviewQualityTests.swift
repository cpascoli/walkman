import XCTest
@testable import Walkman

@MainActor
final class PreviewQualityTests: XCTestCase {

    private func ladder(_ resolutions: [Int]) -> [StreamResolver.Quality] {
        resolutions.map {
            StreamResolver.Quality(id: $0, label: "\($0)p", source: .progressive(URL(string: "https://example.com/\($0)")!))
        }
    }

    func testPicksTheTargetWhenOffered() {
        XCTAssertEqual(PreviewPlayerModel.previewQuality(from: ladder([1080, 720, 480, 360, 240]))?.id, 480)
    }

    func testFallsBelowTheTarget() {
        XCTAssertEqual(PreviewPlayerModel.previewQuality(from: ladder([1080, 720, 360, 144]))?.id, 360)
    }

    func testTakesTheLowestWhenEverythingIsAbove() {
        XCTAssertEqual(PreviewPlayerModel.previewQuality(from: ladder([2160, 1080, 720]))?.id, 720)
    }

    func testLivestreamAutoRung() {
        XCTAssertEqual(PreviewPlayerModel.previewQuality(from: ladder([0]))?.id, 0)
    }

    func testNothingToPick() {
        XCTAssertNil(PreviewPlayerModel.previewQuality(from: []))
    }
}

final class StatedDurationTests: XCTestCase {

    func testReadsDurFromTheStreamURL() {
        let url = URL(string: "https://rr1.googlevideo.com/videoplayback?itag=18&dur=19.110&mime=video%2Fmp4")!
        XCTAssertEqual(StreamResolver.Source.progressive(url).statedDuration, 19.11)
        XCTAssertEqual(StreamResolver.Source.adaptive(video: url, audio: url).statedDuration, 19.11)
    }

    func testNoDurNoDuration() {
        let url = URL(string: "https://example.com/manifest.m3u8")!
        XCTAssertNil(StreamResolver.Source.hls(url).statedDuration)
        XCTAssertNil(StreamResolver.Source.progressive(url).statedDuration)
    }
}

final class QuickStartTests: XCTestCase {

    private let url = URL(string: "https://example.com/v")!

    private func adaptive(_ resolutions: [Int]) -> [StreamResolver.Quality] {
        resolutions.map { StreamResolver.Quality(id: $0, label: "\($0)p", source: .adaptive(video: url, audio: url)) }
    }

    func testPicksTheSmallestWatchableRung() {
        let ladder = adaptive([1080, 720, 480, 360, 240, 144])
        XCTAssertEqual(StreamResolver.quickStart(from: ladder, below: ladder[0]), ladder[3].source)
    }

    func testNothingWhenTheBestIsAlreadyQuick() {
        let ladder = adaptive([360, 240, 144])
        XCTAssertNil(StreamResolver.quickStart(from: ladder, below: ladder[0]))
    }

    func testNothingForAMuxedBest() {
        let best = StreamResolver.Quality(id: 720, label: "720p", source: .progressive(url))
        XCTAssertNil(StreamResolver.quickStart(from: [best] + adaptive([360]), below: best))
    }
}
