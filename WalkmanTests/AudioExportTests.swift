import AVFoundation
import UIKit
import XCTest
@testable import Walkman

final class AudioExportTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = URL.temporaryDirectory.appendingPathComponent("audio-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Two seconds of AAC tone, standing in for a recording.
    private func makeRecording() throws -> URL {
        let url = folder.appendingPathComponent("recording.m4a")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1
        ])
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88_200)!
        buffer.frameLength = 88_200
        for frame in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData![0][frame] = sin(Float(frame) * 2 * .pi * 440 / 44_100) * 0.3
        }
        try file.write(from: buffer)
        return url
    }

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.jpegData(compressionQuality: 0.8)!
    }

    func testExportsTaggedAACAtFullLength() async throws {
        let recording = try makeRecording()
        let destination = folder.appendingPathComponent("Rick Astley - Never Gonna Give You Up.m4a")
        let tags = AudioExporter.Tags(title: "Never Gonna Give You Up", artist: "Rick Astley",
                                      album: "Whenever You Need Somebody", artwork: jpeg())

        try await AudioExporter.export(recordingAt: recording, tags: tags, to: destination)

        let exported = AVURLAsset(url: destination)
        let duration = try await exported.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.1)

        let track = try await exported.loadTracks(withMediaType: .audio).first
        let format = try await track?.load(.formatDescriptions).first
        XCTAssertEqual(format.map(CMFormatDescriptionGetMediaSubType), kAudioFormatMPEG4AAC, "Copied as AAC, not re-encoded to something else")

        let metadata = try await exported.load(.metadata)
        func value(_ identifier: AVMetadataIdentifier) async throws -> Any? {
            try await AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first?.load(.value)
        }
        let title = try await value(.iTunesMetadataSongName) as? String
        let artist = try await value(.iTunesMetadataArtist) as? String
        let album = try await value(.iTunesMetadataAlbum) as? String
        let cover = try await value(.iTunesMetadataCoverArt) as? Data
        XCTAssertEqual(title, "Never Gonna Give You Up")
        XCTAssertEqual(artist, "Rick Astley")
        XCTAssertEqual(album, "Whenever You Need Somebody")
        XCTAssertNotNil(cover.flatMap(UIImage.init(data:)), "Cover art should be a readable image")
    }

    func testTagsPreferAFittingCredit() {
        let entry = HistoryEntry(id: "dQw4w9WgXcQ", title: "Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)")
        let credit = MusicCredit(song: "Never Gonna Give You Up (7\" Mix)", artist: "Rick Astley", album: "Whenever You Need Somebody")

        let tags = AudioExporter.tags(for: entry, credit: credit, artwork: nil)
        XCTAssertEqual(tags, .init(title: "Never Gonna Give You Up", artist: "Rick Astley", album: "Whenever You Need Somebody"))
    }

    func testTagsIgnoreBackgroundMusicAndReadTheTitle() {
        let entry = HistoryEntry(id: "aaaaaaaaaaa", title: "Toto - Africa (Official HD Video)")
        let background = MusicCredit(song: "Strut Funk", artist: "Dougie Wood", album: nil)

        XCTAssertEqual(AudioExporter.tags(for: entry, credit: background, artwork: nil),
                       .init(title: "Africa", artist: "Toto", album: nil))
        XCTAssertEqual(AudioExporter.tags(for: HistoryEntry(id: "bbbbbbbbbbb", title: "Me at the zoo"), credit: nil, artwork: nil),
                       .init(title: "Me at the zoo", artist: nil, album: nil))
    }

    func testFileNamesAreSafe() {
        XCTAssertEqual(AudioExporter.fileName(for: .init(title: "Africa", artist: "Toto")), "Toto - Africa.m4a")
        XCTAssertEqual(AudioExporter.fileName(for: .init(title: "What/Is: Love?", artist: "AC/DC")), "AC DC - What Is  Love.m4a")
        XCTAssertEqual(AudioExporter.fileName(for: .init(title: "  ", artist: nil)), "Recording.m4a")
    }
}
