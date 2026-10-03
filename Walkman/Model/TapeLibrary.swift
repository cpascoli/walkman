import Foundation
import os.log

/// The shelf of tapes, persisted as JSON alongside the recordings catalogue.
@MainActor
final class TapeLibrary: ObservableObject {

    @Published private(set) var tapes: [Tape] = []

    private let fileURL: URL
    private let log = Logger(subsystem: "com.carlopascoli.walkman", category: "TapeLibrary")

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    // MARK: - Queries

    func tape(withID id: UUID) -> Tape? {
        tapes.first { $0.id == id }
    }

    /// Which tapes a given recording already appears on.
    func tapesContaining(_ videoID: String) -> Set<UUID> {
        Set(tapes.filter { $0.contains(videoID) }.map(\.id))
    }

    // MARK: - Tapes

    @discardableResult
    func create(name: String, videoIDs: [String] = []) -> Tape {
        let tape = Tape(name: Self.cleaned(name), videoIDs: videoIDs)
        tapes.append(tape)
        save()
        return tape
    }

    func rename(_ tape: Tape, to name: String) {
        update(tape) { $0.name = Self.cleaned(name) }
    }

    func delete(_ tape: Tape) {
        tapes.removeAll { $0.id == tape.id }
        save()
    }

    func delete(atOffsets offsets: IndexSet) {
        tapes.remove(atOffsets: offsets)
        save()
    }

    func deleteAll() {
        tapes.removeAll()
        save()
    }

    // MARK: - Tracks

    /// Appends a recording. A tape holds each recording once, so re-adding is a no-op.
    func add(_ videoID: String, to tape: Tape) {
        update(tape) { current in
            guard !current.contains(videoID) else { return }
            current.videoIDs.append(videoID)
        }
    }

    /// Appends several recordings in order, skipping any already on the tape.
    func add(_ videoIDs: [String], to tape: Tape) {
        update(tape) { current in
            for videoID in videoIDs where !current.contains(videoID) {
                current.videoIDs.append(videoID)
            }
        }
    }

    func remove(_ videoID: String, from tape: Tape) {
        update(tape) { $0.videoIDs.removeAll { $0 == videoID } }
    }

    /// Toggles membership, for the "add to tape" menu.
    func toggle(_ videoID: String, on tape: Tape) {
        if tape.contains(videoID) {
            remove(videoID, from: tape)
        } else {
            add(videoID, to: tape)
        }
    }

    func moveTracks(in tape: Tape, fromOffsets source: IndexSet, toOffset destination: Int) {
        update(tape) { $0.videoIDs.move(fromOffsets: source, toOffset: destination) }
    }

    func removeTracks(in tape: Tape, atOffsets offsets: IndexSet) {
        update(tape) { $0.videoIDs.remove(atOffsets: offsets) }
    }

    /// Drops a recording from every tape — used when its entry is deleted outright.
    func purge(_ videoID: String) {
        var changed = false
        for index in tapes.indices where tapes[index].contains(videoID) {
            tapes[index].videoIDs.removeAll { $0 == videoID }
            tapes[index].updatedAt = .now
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Mutation plumbing

    private func update(_ tape: Tape, _ change: (inout Tape) -> Void) {
        guard let index = tapes.firstIndex(where: { $0.id == tape.id }) else { return }
        var updated = tapes[index]
        change(&updated)
        guard updated != tapes[index] else { return }
        updated.updatedAt = .now
        tapes[index] = updated
        save()
    }

    private static func cleaned(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Tape" : trimmed
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("tapes.json")
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            tapes = try JSONDecoder().decode([Tape].self, from: Data(contentsOf: fileURL))
        } catch {
            log.error("Failed to load tapes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        let snapshot = tapes
        let url = fileURL
        Task.detached(priority: .utility) {
            do {
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            } catch {
                Logger(subsystem: "com.carlopascoli.walkman", category: "TapeLibrary")
                    .error("Failed to save tapes: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
