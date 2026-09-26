import AVFoundation
import SwiftUI
import UIKit

/// Turns a recording into a tagged audio file for use outside the app — to
/// AirDrop to a Mac and add to the Music app, say.
///
/// M4A rather than MP3: iOS can't encode MP3, and the recording's audio is
/// already AAC, so it's copied across untouched — no quality lost, and done in
/// a moment.
enum AudioExporter {

    struct Tags: Equatable {
        var title: String
        var artist: String?
        var album: String? = nil
        /// JPEG.
        var artwork: Data? = nil
    }

    enum ExportError: LocalizedError {
        case noAudio
        case failed(String?)

        var errorDescription: String? {
            switch self {
            case .noAudio: "This recording has no sound to export."
            case .failed(let reason): reason ?? "The audio couldn't be exported."
            }
        }
    }

    /// Writes the recording's audio to `destination` as a tagged M4A.
    static func export(recordingAt url: URL, tags: Tags, to destination: URL) async throws {
        // At its real length, whenever it was recorded.
        let recording = try await StreamResolver.makeLocalAsset(at: url)
        guard let audio = try await recording.loadTracks(withMediaType: .audio).first else {
            throw ExportError.noAudio
        }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.noAudio
        }
        try track.insertTimeRange(try await audio.load(.timeRange), of: audio, at: .zero)
        withExtendedLifetime(recording) {}

        // Passthrough keeps the AAC as it is; re-encode only if it can't.
        let passthrough = await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough, with: composition, outputFileType: .m4a
        )
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: passthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A
        ) else {
            throw ExportError.failed(nil)
        }
        session.metadata = metadata(for: tags)

        try? FileManager.default.removeItem(at: destination)
        if #available(iOS 18, *) {
            try await session.export(to: destination, as: .m4a)
        } else {
            try await legacyExport(session, to: destination)
        }
    }

    @available(iOS, deprecated: 18, message: "Only for iOS 17; newer systems use export(to:as:).")
    private static func legacyExport(_ session: AVAssetExportSession, to destination: URL) async throws {
        session.outputURL = destination
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else { throw ExportError.failed(session.error?.localizedDescription) }
    }

    /// iTunes-style tags, which the Music app reads.
    static func metadata(for tags: Tags) -> [AVMetadataItem] {
        var items = [item(.iTunesMetadataSongName, tags.title as NSString)]
        if let artist = tags.artist { items.append(item(.iTunesMetadataArtist, artist as NSString)) }
        if let album = tags.album { items.append(item(.iTunesMetadataAlbum, album as NSString)) }
        if let artwork = tags.artwork {
            let cover = item(.iTunesMetadataCoverArt, artwork as NSData)
            cover.dataType = kCMMetadataBaseDataType_JPEG as String
            items.append(cover)
        }
        return items
    }

    private static func item(_ identifier: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMutableMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        item.extendedLanguageTag = "und"
        return item
    }

    // MARK: - Tags

    /// What to call the file and tag it with: YouTube's credit for the song
    /// when it has one that fits, otherwise the title read as "Artist - Song".
    static func tags(for entry: HistoryEntry, credit: MusicCredit?, artwork: Data?) -> Tags {
        let video = SearchResult(id: entry.id, title: entry.title, channel: "", snippet: "", duration: "",
                                 viewCount: "", published: "", thumbnailURL: nil)
        if let credit, SongIdentifier.accepted(credit, for: video) != nil {
            return Tags(title: TrackMatching.bareTrack(credit.song, dropSubtitles: true),
                        artist: TrackMatching.leadArtist(credit.artist),
                        album: credit.album,
                        artwork: artwork)
        }
        let guess = TrackMatching.guess(title: entry.title, channel: "")
        return Tags(title: TrackMatching.bareTrack(guess.track), artist: guess.artist, album: nil, artwork: artwork)
    }

    /// "Artist - Song.m4a", safe as a file name.
    static func fileName(for tags: Tags) -> String {
        let name = [tags.artist, tags.title].compactMap { $0 }.joined(separator: " - ")
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (safe.isEmpty ? "Recording" : String(safe.prefix(120))) + ".m4a"
    }

    /// Square cover art from the video's thumbnail. The widescreen sizes have
    /// no letterboxing, so a centre crop is clean; the largest isn't always there.
    static func artwork(for videoID: String) async -> Data? {
        for size in ["maxresdefault", "mqdefault"] {
            guard let url = URL(string: "https://i.ytimg.com/vi/\(videoID)/\(size).jpg"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data), let square = centreSquare(of: image) else { continue }
            return square.jpegData(compressionQuality: 0.85)
        }
        return nil
    }

    private static func centreSquare(of image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let side = min(cgImage.width, cgImage.height)
        let crop = CGRect(x: (cgImage.width - side) / 2, y: (cgImage.height - side) / 2, width: side, height: side)
        return cgImage.cropping(to: crop).map { UIImage(cgImage: $0) }
    }
}

// MARK: - Presenting

/// Runs an export for a list and hands the file to the share sheet.
@MainActor
final class AudioExport: ObservableObject {

    struct File: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @Published private(set) var isExporting = false
    @Published var file: File?
    @Published var errorMessage: String?

    func export(_ entry: HistoryEntry, from recording: URL) {
        guard !isExporting else { return }
        isExporting = true

        Task {
            defer { isExporting = false }
            // Both are nice-to-haves: offline, the file still gets a title.
            async let credit = try? YouTubeSearch().musicCredit(for: entry.id)
            async let artwork = AudioExporter.artwork(for: entry.id)
            let tags = AudioExporter.tags(for: entry, credit: await credit ?? nil, artwork: await artwork)

            let folder = URL.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
            try? FileManager.default.removeItem(at: folder) // Last time's, already shared.
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(AudioExporter.fileName(for: tags))

            do {
                try await AudioExporter.export(recordingAt: recording, tags: tags, to: destination)
                file = File(url: destination)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension View {
    /// The progress, share sheet and errors for an `AudioExport`.
    func presentingAudioExport(_ export: AudioExport) -> some View {
        modifier(AudioExportPresenter(export: export))
    }
}

private struct AudioExportPresenter: ViewModifier {
    @ObservedObject var export: AudioExport

    func body(content: Content) -> some View {
        content
            .overlay {
                if export.isExporting {
                    ProgressView("Exporting audio…")
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.label)
                        .padding()
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("exportingAudio")
                }
            }
            .sheet(item: $export.file) { file in
                ShareSheet(items: [file.url])
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
            .alert("Couldn't Export", isPresented: Binding(
                get: { export.errorMessage != nil },
                set: { if !$0 { export.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(export.errorMessage ?? "")
            }
    }
}

/// The system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
