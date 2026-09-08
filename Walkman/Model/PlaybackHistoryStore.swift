import Foundation
import YouTubeKit
import os.log

/// Persists the list of played videos as JSON in Application Support.
///
/// The history is small (one record per video, deduplicated by ID), so it's
/// loaded fully into memory and rewritten on change.
@MainActor
final class PlaybackHistoryStore: ObservableObject {

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileURL: URL
    private var pendingLookups: Set<String> = []
    private let log = Logger(subsystem: "com.carlopascoli.walkman", category: "History")

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    // MARK: - Queries

    /// Most recently played first, optionally filtered by a search query.
    func entries(matching query: String) -> [HistoryEntry] {
        entries.filter { $0.matches(query) }
    }

    // MARK: - Mutations

    /// Records a play. An existing entry is moved to the top and its count bumped,
    /// keeping any title already resolved for it.
    func recordPlay(videoID: String, title: String? = nil, thumbnailURL: URL? = nil) {
        if let index = entries.firstIndex(where: { $0.id == videoID }) {
            var entry = entries.remove(at: index)
            entry.lastPlayedAt = .now
            entry.playCount += 1
            if let title, !title.isEmpty { entry.title = title }
            if let thumbnailURL { entry.thumbnailURL = thumbnailURL }
            entries.insert(entry, at: 0)
        } else {
            entries.insert(
                HistoryEntry(id: videoID, title: title ?? videoID, thumbnailURL: thumbnailURL),
                at: 0
            )
        }
        save()
    }

    /// Fills in details that arrive after playback starts, without counting a new play.
    func updateDetails(videoID: String, title: String?, thumbnailURL: URL?) {
        guard let index = entries.firstIndex(where: { $0.id == videoID }) else { return }
        var entry = entries[index]
        if let title, !title.isEmpty { entry.title = title }
        if let thumbnailURL { entry.thumbnailURL = thumbnailURL }
        guard entry != entries[index] else { return }
        entries[index] = entry
        save()
    }

    /// Fills in a real title for an entry that only has its video ID — which is the
    /// case for plays through the embedded engine, since that path never runs
    /// extraction. Without this, history search can only match on ID.
    func resolveDetailsIfNeeded(videoID: String) {
        guard let entry = entries.first(where: { $0.id == videoID }), entry.title == videoID else { return }
        guard pendingLookups.insert(videoID).inserted else { return }

        Task { [weak self] in
            let metadata = try? await YouTube(videoID: videoID, methods: [.local, .remote]).metadata
            guard let self else { return }
            self.pendingLookups.remove(videoID)
            guard let metadata else { return }
            self.updateDetails(videoID: videoID, title: metadata.title, thumbnailURL: metadata.thumbnail?.url)
        }
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func remove(atOffsets offsets: IndexSet, in visible: [HistoryEntry]) {
        let ids = Set(offsets.map { visible[$0].id })
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("playback-history.json")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([HistoryEntry].self, from: data)
            entries = decoded.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
        } catch {
            // A corrupt file shouldn't block the app; start fresh instead.
            log.error("Failed to load history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        let snapshot = entries
        let url = fileURL
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                Logger(subsystem: "com.carlopascoli.walkman", category: "History")
                    .error("Failed to save history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
