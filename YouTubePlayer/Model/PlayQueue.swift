import Foundation

/// The running order for continuous playback.
///
/// A snapshot of the library taken when the user picks something to play. It has
/// to be a snapshot: every play bumps its entry to the top of the history, so
/// re-deriving the order after each track would make the sequence eat itself.
///
/// The queue wraps around at the end, which is the tape-side behaviour — it
/// keeps going rather than stopping dead.
@MainActor
final class PlayQueue: ObservableObject {

    @Published private(set) var ids: [String] = []
    @Published private(set) var index: Int = 0

    var current: String? {
        ids.indices.contains(index) ? ids[index] : nil
    }

    var count: Int { ids.count }

    /// Rebuilds the running order from the library, rotated so `videoID` is first.
    func rebuild(from entries: [HistoryEntry], startingAt videoID: String) {
        let all = entries.map(\.id)

        guard let start = all.firstIndex(of: videoID) else {
            // Not in the library yet (first play of a fresh ID) — lead with it.
            ids = [videoID] + all
            index = 0
            return
        }

        ids = Array(all[start...]) + Array(all[..<start])
        index = 0
    }

    /// Advances to the next tape, wrapping at the end. `nil` when there's nothing queued.
    func advance() -> String? {
        guard !ids.isEmpty else { return nil }
        index = (index + 1) % ids.count
        return ids[index]
    }

    func clear() {
        ids = []
        index = 0
    }
}
