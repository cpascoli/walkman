import Foundation

/// Builds a draft tape of tracks like a given video: Last.fm names the song and
/// finds similar ones, then each is looked up on YouTube.
@MainActor
final class SimilarTapeModel: ObservableObject {

    enum Phase: Equatable {
        case identifying
        case findingSimilar
        case searchingYouTube(done: Int, of: Int)
        case finished
        case failed(String)
    }

    /// One track on the draft: the video found, and the Last.fm track it stands for.
    struct Item: Identifiable, Hashable {
        var id: String { video.id }
        let video: SearchResult
        /// Nil for the video the tape was made from.
        let source: LastFMTrack?
    }

    static let trackCount = 20

    @Published private(set) var phase: Phase = .identifying
    /// The song Last.fm matched the video to.
    @Published private(set) var seed: LastFMTrack?
    /// The original first, then Last.fm's order, most similar first.
    @Published private(set) var items: [Item] = []
    /// Tracks Last.fm suggested that couldn't be found on YouTube.
    @Published private(set) var missing: [LastFMTrack] = []

    let original: SearchResult

    private var task: Task<Void, Never>?
    private var tracks: [LastFMTrack] = []
    private var found: [Int: SearchResult] = [:]
    private var searched: Set<Int> = []
    /// Remembered so results still arriving don't bring a deleted track back.
    private var removed: Set<String> = []

    init(original: SearchResult) {
        self.original = original
        items = [Item(video: original, source: nil)]
    }

    deinit {
        task?.cancel()
    }

    var isWorking: Bool {
        switch phase {
        case .finished, .failed: false
        default: true
        }
    }

    func start() {
        guard task == nil else { return }
        run()
    }

    func retry() {
        task?.cancel()
        run()
    }

    // MARK: - Editing

    func remove(atOffsets offsets: IndexSet) {
        removed.formUnion(offsets.map { items[$0].id })
        items.remove(atOffsets: offsets)
    }

    /// Only once the draft is finished; until then it's rebuilt as results land.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !isWorking else { return }
        items.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Generating

    private enum Event {
        case identified(LastFMTrack)
        case similar([LastFMTrack])
        case searched(index: Int, result: SearchResult?)
    }

    private enum GenerationError: LocalizedError {
        case unknownSong(String)
        case nothingSimilar(LastFMTrack)

        var errorDescription: String? {
            switch self {
            case .unknownSong(let title):
                "Last.fm doesn't recognise “\(title)” as a song."
            case .nothingSimilar(let track):
                "Last.fm has no similar tracks for \(track.artist) — \(track.name)."
            }
        }
    }

    private func run() {
        guard let apiKey = LastFMCredentials.apiKey else {
            phase = .failed("Add your Last.fm API key in Settings to make tapes of similar tracks.")
            return
        }

        seed = nil
        tracks = []
        found = [:]
        searched = []
        phase = .identifying
        rebuild()

        let original = original
        let lastFM = LastFM(apiKey: apiKey)

        // The pipeline only reports back, and only to a model that still
        // exists, so leaving the screen releases the model and its deinit
        // cancels the work.
        task = Task { [weak self] in
            do {
                try await SimilarTapeModel.generate(from: original, with: lastFM) { event in
                    self?.handle(event)
                }
                self?.phase = .finished
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func handle(_ event: Event) {
        switch event {
        case .identified(let track):
            seed = track
            phase = .findingSimilar
        case .similar(let similar):
            tracks = similar
            phase = .searchingYouTube(done: 0, of: similar.count)
        case .searched(let index, let result):
            searched.insert(index)
            found[index] = result
            phase = .searchingYouTube(done: searched.count, of: tracks.count)
            rebuild()
        }
    }

    private func rebuild() {
        var seen: Set<String> = [original.id]
        var drafted: [Item] = removed.contains(original.id) ? [] : [Item(video: original, source: nil)]

        for (index, track) in tracks.enumerated() {
            guard let video = found[index],
                  !removed.contains(video.id),
                  seen.insert(video.id).inserted else { continue }
            drafted.append(Item(video: video, source: track))
        }

        items = drafted
        missing = tracks.indices
            .filter { searched.contains($0) && found[$0] == nil }
            .map { tracks[$0] }
    }

    private static func generate(
        from original: SearchResult,
        with lastFM: LastFM,
        report: @escaping @MainActor (Event) -> Void
    ) async throws {
        guard let seed = try await identify(original, with: lastFM) else {
            throw GenerationError.unknownSong(original.title)
        }
        try Task.checkCancellation()
        await report(.identified(seed))

        let similar = try await lastFM.similarTracks(to: seed, limit: trackCount)
        guard !similar.isEmpty else { throw GenerationError.nothingSimilar(seed) }
        try Task.checkCancellation()
        await report(.similar(similar))

        // A few searches at a time: quick, without hammering YouTube.
        let youTube = YouTubeSearch()
        try await withThrowingTaskGroup(of: (Int, SearchResult?).self) { group in
            var next = 0
            func enqueue() {
                guard next < similar.count else { return }
                let index = next, track = similar[index]
                next += 1
                group.addTask {
                    let results = (try? await youTube.search("\(track.artist) \(track.name)").results) ?? []
                    return (index, TrackMatching.bestMatch(for: track, in: Array(results.prefix(10))))
                }
            }

            for _ in 0..<4 { enqueue() }
            for try await (index, result) in group {
                try Task.checkCancellation()
                await report(.searched(index: index, result: result))
                enqueue()
            }
        }
    }

    /// What song the video is, per Last.fm: as the title reads, then on the
    /// title alone in case the artist guess was wrong.
    private static func identify(_ video: SearchResult, with lastFM: LastFM) async throws -> LastFMTrack? {
        let guess = TrackMatching.guess(title: video.title, channel: video.channel)

        var attempts: [String?] = [guess.artist]
        if guess.artist != nil { attempts.append(nil) }

        for artist in attempts {
            if let found = try await lastFM.searchTracks(guess.track, artist: artist, limit: 1).first {
                return found
            }
        }
        return nil
    }
}
