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

    /// Finds what to save for a video that isn't playing, for batch downloads.
    typealias SourceResolver = @MainActor (_ videoID: String) async throws -> StreamResolver.Source

    /// Video IDs with a file on disk. Published so history rows update live.
    @Published private(set) var downloadedIDs: Set<String> = []
    @Published private(set) var statuses: [String: Status] = [:]
    /// A batch download's videos still to go, the one in progress first.
    @Published private(set) var batch: [String] = []

    private let directory: URL
    private var tasks: [String: Task<Void, Never>] = [:]
    private var sessions: [String: AVAssetExportSession] = [:]
    private var batchTask: Task<Void, Never>?
    private var batchResolver: SourceResolver?
    private let log = Logger(subsystem: "com.carlopascoli.walkman", category: "Downloads")

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

    /// Downloads each video not already on the device, one at a time, skipping
    /// past any that fail. Starting it again picks up whatever's left; while
    /// one is running, more videos join the end of it.
    func downloadAll(_ videoIDs: [String], resolve: @escaping SourceResolver) {
        var seen = Set(batch)
        batch += videoIDs.filter { !downloadedIDs.contains($0) && seen.insert($0).inserted }
        batchResolver = resolve
        guard batchTask == nil, !batch.isEmpty else { return }

        batchTask = Task { [weak self] in
            await self?.runBatch()
        }
    }

    /// Stops a batch download, including the video in progress.
    func cancelBatch() {
        batchTask?.cancel()
        batchTask = nil
        let current = batch.first
        batch = []
        if let current, tasks[current] != nil {
            cancel(videoID: current)
        }
    }

    private func runBatch() async {
        // Keep going for a while if the app is left mid-batch.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Batch download")
        defer {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }

        while let videoID = batch.first, let resolve = batchResolver, !Task.isCancelled {
            // Already saved, or already being saved from the deck.
            if !downloadedIDs.contains(videoID), tasks[videoID] == nil {
                statuses[videoID] = .preparing
                do {
                    let source = try await resolve(videoID)
                    try Task.checkCancellation()
                    if case .hls = source { throw DownloadError.liveStreamNotDownloadable }

                    let task = Task<Void, Never> { [weak self] in
                        await self?.performExport(videoID: videoID, source: source)
                    }
                    tasks[videoID] = task
                    await task.value
                } catch is CancellationError {
                    statuses[videoID] = nil
                } catch {
                    log.error("Batch download couldn't start \(videoID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    statuses[videoID] = .failed(error.localizedDescription)
                }
            }
            guard !Task.isCancelled else { break }
            if batch.first == videoID { batch.removeFirst() }
        }

        if !Task.isCancelled {
            batchTask = nil
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
