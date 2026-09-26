import Foundation

/// What to play, and the running order it belongs to.
struct PlaybackRequest: Equatable {
    let videoID: String
    /// The full running order this video sits in — a tape's tracks, or the
    /// whole catalogue when playing from All Recordings.
    let running: [String]
    /// Shown on the deck, e.g. the tape's name.
    let sourceName: String
}

/// The running order for continuous playback.
///
/// A snapshot of whatever list the user played from. It has to be a snapshot:
/// playing a recording bumps it to the top of the catalogue, so re-deriving the
/// order after each track would make the sequence eat itself.
///
/// The queue wraps at both ends, which is the tape-side behaviour — it keeps
/// going rather than stopping dead.
@MainActor
final class PlayQueue: ObservableObject {

    @Published private(set) var ids: [String] = []
    @Published private(set) var index: Int = 0
    /// The name of the list being played, for display on the deck.
    @Published private(set) var sourceName: String = ""

    var current: String? {
        ids.indices.contains(index) ? ids[index] : nil
    }

    var count: Int { ids.count }

    /// Position within the running order, 1-based, for the deck readout.
    var position: Int { ids.isEmpty ? 0 : index + 1 }

    /// Rebuilds the running order, rotated so `videoID` leads.
    func rebuild(ids all: [String], startingAt videoID: String, sourceName: String) {
        self.sourceName = sourceName

        guard let start = all.firstIndex(of: videoID) else {
            // Not in the list yet (a freshly typed ID) — lead with it.
            ids = [videoID] + all
            index = 0
            return
        }

        ids = Array(all[start...]) + Array(all[..<start])
        index = 0
    }

    func rebuild(from request: PlaybackRequest) {
        rebuild(ids: request.running, startingAt: request.videoID, sourceName: request.sourceName)
    }

    /// Advances to the next track, wrapping at the end. `nil` when nothing is queued.
    func advance() -> String? {
        guard !ids.isEmpty else { return nil }
        index = (index + 1) % ids.count
        return ids[index]
    }

    /// Steps back one track, wrapping at the start.
    func previous() -> String? {
        guard !ids.isEmpty else { return nil }
        index = (index - 1 + ids.count) % ids.count
        return ids[index]
    }

    func clear() {
        ids = []
        index = 0
        sourceName = ""
    }
}
