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
        case notASingleSong
        case unknownSong(String)
        case nothingSimilar(LastFMTrack)

        var errorDescription: String? {
            switch self {
            case .notASingleSong:
                "This looks like a set, a concert or a stream rather than a single song, so there's no one song to match."
            case .unknownSong(let title):
                "Couldn't work out which song “\(title)” is."
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
        // The credit is a bonus; without it the title still gets a reading.
        let credit = try? await YouTubeSearch().musicCredit(for: original.id)
        let outcome = try await SongIdentifier.identify(original, credit: credit) { track, artist in
            try await lastFM.searchTracks(track, artist: artist, limit: 5)
        }

        var seed: LastFMTrack
        switch outcome {
        case .song(let track): seed = track
        case .notASingleSong: throw GenerationError.notASingleSong
        case .unknown: throw GenerationError.unknownSong(original.title)
        }
        try Task.checkCancellation()
        await report(.identified(seed))

        var similar = try await lastFM.similarTracks(to: seed, limit: trackCount)
        if similar.isEmpty, let better = try await bestKnownVersion(of: seed, with: lastFM) {
            // A cover or a small upload may have no listening data of its own,
            // but the song's best-known version usually does.
            seed = better
            await report(.identified(seed))
            similar = try await lastFM.similarTracks(to: seed, limit: trackCount)
        }
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

    /// The most-listened track of the same name by someone else — the
    /// original, when the seed is a cover.
    private static func bestKnownVersion(of seed: LastFMTrack, with lastFM: LastFM) async throws -> LastFMTrack? {
        let name = TrackMatching.normalized(TrackMatching.bareTrack(seed.name, dropSubtitles: true))
        return try await lastFM.searchTracks(TrackMatching.bareTrack(seed.name, dropSubtitles: true), limit: 10)
            .filter {
                TrackMatching.normalized(TrackMatching.bareTrack($0.name, dropSubtitles: true)) == name
                    && TrackMatching.normalized($0.artist) != TrackMatching.normalized(seed.artist)
                    && !TrackMatching.looksLikeVideoTitle($0.name, searchedFor: seed.name)
            }
            .max { ($0.listeners ?? 0) < ($1.listeners ?? 0) }
    }
}
