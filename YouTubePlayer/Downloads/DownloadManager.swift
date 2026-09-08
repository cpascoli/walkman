import AVFoundation
import Combine
import Foundation
import UIKit
import os.log

/// Saves videos to the device as playable `.mp4` files, keyed by video ID.
///
/// YouTube's high-resolution tracks are video-only, so a download is produced by
/// exporting the same `AVComposition` the player uses. The export runs in
/// passthrough mode, which remuxes the existing H.264 + AAC tracks into an MP4
/// container without re-encoding.
///
/// The presence of the file on disk is the single source of truth for
/// "is this downloaded", so downloads survive clearing the history.
@MainActor
final class DownloadManager: ObservableObject {

    enum Status: Equatable {
        case notDownloaded
        case preparing
        case downloading(progress: Double)
        case downloaded
        case failed(String)

        var isActive: Bool {
            switch self {
            case .preparing, .downloading: return true
            case .notDownloaded, .downloaded, .failed: return false
            }
        }
    }

    enum DownloadError: LocalizedError {
        case liveStreamNotDownloadable
        case exportUnavailable

        var errorDescription: String? {
            switch self {
            case .liveStreamNotDownloadable: return "Live streams can't be downloaded."
            case .exportUnavailable: return "This video can't be exported to MP4."
            }
        }
    }

    /// Video IDs with a file on disk. Published so history rows update live.
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var statuses: [String: Status] = [:]

    private let directory: URL
    private var tasks: [String: Task<Void, Never>] = [:]
    private var sessions: [String: AVAssetExportSession] = [:]
    private let log = Logger(subsystem: "com.carlopascoli.mytubeplayer", category: "Downloads")

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        scanDisk()
    }

    // MARK: - Queries

    func status(for videoID: String) -> Status {
        if let status = statuses[videoID] { return status }
        return downloadedIDs.contains(videoID) ? .downloaded : .notDownloaded
    }

    func isDownloaded(_ videoID: String) -> Bool {
        downloadedIDs.contains(videoID)
    }

    /// The on-disk file for a video, or `nil` if it isn't downloaded.
    func localURL(for videoID: String) -> URL? {
        let url = fileURL(for: videoID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fileSize(for videoID: String) -> Int64? {
        guard let url = localURL(for: videoID),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return Int64(size)
    }

    var totalBytesOnDisk: Int64 {
        downloadedIDs.compactMap { fileSize(for: $0) }.reduce(0, +)
    }

    // MARK: - Downloading

    func download(videoID: String, source: StreamResolver.Source) {
        guard tasks[videoID] == nil, !downloadedIDs.contains(videoID) else { return }

        if case .hls = source {
            statuses[videoID] = .failed(DownloadError.liveStreamNotDownloadable.localizedDescription)
            return
        }

        statuses[videoID] = .preparing
        tasks[videoID] = Task { [weak self] in
            await self?.performExport(videoID: videoID, source: source)
        }
    }

    func cancel(videoID: String) {
        sessions[videoID]?.cancelExport()
        sessions[videoID] = nil
        tasks[videoID]?.cancel()
        tasks[videoID] = nil
        statuses[videoID] = nil
        try? FileManager.default.removeItem(at: fileURL(for: videoID))
    }

    func delete(videoID: String) {
        cancel(videoID: videoID)
        try? FileManager.default.removeItem(at: fileURL(for: videoID))
        downloadedIDs.remove(videoID)
        statuses[videoID] = nil
    }

    func deleteAll() {
        for id in downloadedIDs { delete(videoID: id) }
    }

    private func performExport(videoID: String, source: StreamResolver.Source) async {
        // Keep exporting for a while if the user leaves the app mid-download.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Download \(videoID)")
        defer {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }

        let destination = fileURL(for: videoID)
        try? FileManager.default.removeItem(at: destination)

        do {
            let asset = try await StreamResolver.makeAsset(for: source)
            try Task.checkCancellation()

            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough),
                  await AVAssetExportSession.compatibility(
                      ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: .mp4
                  ) else {
                throw DownloadError.exportUnavailable
            }

            sessions[videoID] = session
            statuses[videoID] = .downloading(progress: 0)

            try await runExport(session, to: destination, videoID: videoID)
            try Task.checkCancellation()

            downloadedIDs.insert(videoID)
            statuses[videoID] = .downloaded
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            statuses[videoID] = nil
        } catch {
            log.error("Download failed for \(videoID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: destination)
            statuses[videoID] = .failed(error.localizedDescription)
        }

        sessions[videoID] = nil
        tasks[videoID] = nil
    }

    private func runExport(_ session: AVAssetExportSession, to destination: URL, videoID: String) async throws {
        if #available(iOS 18.0, *) {
            let progress = Task { [weak self] in
                for await state in session.states(updateInterval: 0.25) {
                    guard let self else { return }
                    if case .exporting(let fraction) = state {
                        self.statuses[videoID] = .downloading(progress: fraction.fractionCompleted)
                    }
                }
            }
            defer { progress.cancel() }
            try await session.export(to: destination, as: .mp4)
        } else {
            try await runLegacyExport(session, to: destination, videoID: videoID)
        }
    }

    /// Pre-iOS 18 export path. Marked deprecated so the deprecated members it
    /// necessarily uses don't warn at every call site.
    @available(iOS, deprecated: 18.0)
    private func runLegacyExport(_ session: AVAssetExportSession, to destination: URL, videoID: String) async throws {
        session.outputURL = destination
        session.outputFileType = .mp4

        let progress = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                self.statuses[videoID] = .downloading(progress: Double(session.progress))
            }
        }
        defer { progress.cancel() }

        await session.export()

        switch session.status {
        case .completed: return
        case .cancelled: throw CancellationError()
        default: throw session.error ?? DownloadError.exportUnavailable
        }
    }

    // MARK: - Disk

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return base.appendingPathComponent("Downloads", isDirectory: true)
    }

    private func fileURL(for videoID: String) -> URL {
        directory.appendingPathComponent("\(videoID).mp4")
    }

    private func scanDisk() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        downloadedIDs = Set(
            files.filter { $0.pathExtension == "mp4" }.map { $0.deletingPathExtension().lastPathComponent }
        )
    }
}
