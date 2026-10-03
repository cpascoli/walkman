import Foundation

/// Winds more onto a tape: tracks like its last one, found the same way as a
/// new tape of similar tracks, then added to the end in Last.fm's order.
@MainActor
final class TapeExtensionModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// Looking the last track up on YouTube, then asking Last.fm what it is.
        case identifying
        case findingSimilar
        case searchingYouTube(done: Int, of: Int)
        /// How many tracks went on, and the song they're like.
        case added(Int, like: LastFMTrack)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private var task: Task<Void, Never>?
    private var seed: LastFMTrack?
    private var trackCount = 0
    private var found: [Int: SearchResult] = [:]
    private var searched = 0

    deinit {
        task?.cancel()
    }

    var isWorking: Bool {
        switch phase {
        case .identifying, .findingSimilar, .searchingYouTube: true
        case .idle, .added, .failed: false
        }
    }

    private enum ExtensionError: LocalizedError {
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let title): "Couldn't find “\(title)” on YouTube to see what it is."
            }
        }
    }

    /// Finds tracks like `last` and hands the new ones over, most similar
    /// first, leaving out any already on the tape.
    func extend(from last: HistoryEntry, skipping onTape: [String], add: @escaping ([SearchResult]) -> Void) {
        guard !isWorking else { return }
        guard let apiKey = LastFMCredentials.apiKey else {
            phase = .failed("Add your Last.fm API key in Settings to add similar tracks.")
            return
        }

        seed = nil
        trackCount = 0
        found = [:]
        searched = 0
        phase = .identifying

        let lastFM = LastFM(apiKey: apiKey)

        // As with a new tape, only a model that still exists hears back, so
        // leaving the tape cancels the work.
        task = Task { [weak self] in
            do {
                guard let original = try await YouTubeSearch().video(id: last.id, title: last.title) else {
                    throw ExtensionError.notFound(last.title)
                }
                try await SimilarTapeModel.generate(from: original, with: lastFM) { event in
                    self?.handle(event)
                }
                self?.finish(skipping: Set(onTape + [last.id]), add: add)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func handle(_ event: SimilarTapeModel.Event) {
        switch event {
        case .identified(let track):
            seed = track
            phase = .findingSimilar
        case .similar(let tracks):
            trackCount = tracks.count
            phase = .searchingYouTube(done: 0, of: trackCount)
        case .searched(let index, let result):
            searched += 1
            found[index] = result
            phase = .searchingYouTube(done: searched, of: trackCount)
        }
    }

    private func finish(skipping onTape: Set<String>, add: ([SearchResult]) -> Void) {
        var seen = onTape
        let new = found.keys.sorted()
            .compactMap { found[$0] }
            .filter { seen.insert($0.id).inserted }
        add(new)
        phase = seed.map { .added(new.count, like: $0) } ?? .idle
    }
}
