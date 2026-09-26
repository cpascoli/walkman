import AVFoundation
import Combine
import YouTubeKit

/// Streams a search result for previewing, at a middling quality so it starts
/// quickly.
///
/// Deliberately separate from `NativePlayerModel`: a preview isn't a play, so it
/// leaves the deck, the play queue, the history and the lock screen alone.
@MainActor
final class PreviewPlayerModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    /// The resolution a preview aims for.
    static let targetResolution = 480

    @Published private(set) var state: State = .idle
    @Published private(set) var isPlaying = false
    /// The quality actually streaming, e.g. "480p".
    @Published private(set) var qualityLabel: String?

    let player = AVPlayer()

    private var videoID: String?
    private var loadTask: Task<Void, Never>?
    private var statusObservation: AnyCancellable?

    init() {
        statusObservation = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = status == .playing }
    }

    func load(videoID: String) {
        guard self.videoID != videoID || state != .ready else { return }
        self.videoID = videoID
        loadTask?.cancel()
        player.replaceCurrentItem(with: nil)
        qualityLabel = nil
        state = .loading

        loadTask = Task {
            do {
                let video = YouTube(videoID: videoID, methods: [.local, .remote])
                let (qualities, _) = try await StreamResolver.qualities(for: video)
                guard let quality = Self.previewQuality(from: qualities) else {
                    throw StreamResolver.ResolverError.noPlayableStream
                }

                // Playing in about a second, while the preview quality is built.
                var startedQuick = false
                if let quick = StreamResolver.quickStart(from: qualities, below: quality),
                   let asset = try? await StreamResolver.makeAsset(for: quick),
                   !Task.isCancelled, self.videoID == videoID {
                    player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                    player.play()
                    startedQuick = true
                    qualityLabel = qualities.first { $0.source == quick }?.label
                    state = .ready
                }

                let item: AVPlayerItem
                do {
                    item = try await StreamResolver.makePlayerItem(for: quality.source)
                } catch where state == .ready && !(error is CancellationError) {
                    // The quick stream is already playable; settle for it.
                    return
                }
                guard !Task.isCancelled, self.videoID == videoID else { return }
                if startedQuick {
                    upgrade(to: item)
                } else {
                    player.replaceCurrentItem(with: item)
                    player.play()
                }
                qualityLabel = quality.label
                state = .ready
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.videoID == videoID else { return }
                state = .failed((error as? YouTubeKitError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Swaps in the better item where the quick one has got to, and keeps it
    /// playing only if it was — the user may have paused it meanwhile.
    private func upgrade(to item: AVPlayerItem) {
        let position = player.currentTime()
        let wasPlaying = player.rate != 0
        player.replaceCurrentItem(with: item)
        if position.isValid, position.seconds > 0 {
            player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if wasPlaying { player.play() }
    }

    func retry() {
        guard let videoID else { return }
        self.videoID = nil
        load(videoID: videoID)
    }

    /// The preview stops when it's closed, which is when this goes away — not
    /// when its view disappears. Going full screen makes the view disappear
    /// too, and stopping then would pull the video out from under the
    /// full-screen player.
    deinit {
        loadTask?.cancel()
        player.pause()
    }

    /// The highest quality at or below the target, else the lowest there is.
    /// A livestream's single "auto" rung is taken as is.
    static func previewQuality(from qualities: [StreamResolver.Quality]) -> StreamResolver.Quality? {
        qualities.filter { $0.id <= targetResolution }.max { $0.id < $1.id }
            ?? qualities.min { $0.id < $1.id }
    }
}
