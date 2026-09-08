import AVFoundation
import Combine
import Foundation
import YouTubeKit

/// Resolves a YouTube video to a direct stream URL with YouTubeKit and plays it in `AVPlayer`.
///
/// Playback is configured for background audio: the session uses the `.playback`
/// category and lock-screen controls are wired through `NowPlayingController`.
@MainActor
final class NativePlayerModel: ObservableObject {

    typealias Quality = StreamResolver.Quality

    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var videoID: String?
    @Published private(set) var title: String?
    @Published private(set) var thumbnailURL: URL?
    @Published private(set) var qualities: [Quality] = []
    @Published private(set) var selectedQualityID: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLive = false
    /// True when the current video is coming off disk rather than the network.
    @Published private(set) var isPlayingLocalFile = false

    /// Falls back to YouTubeKit's remote extractor when local extraction breaks.
    /// Costs a round trip, but keeps working when YouTube changes its unofficial API.
    @Published var usesRemoteFallback = true

    let player = AVPlayer()

    private let history: PlaybackHistoryStore
    private let downloads: DownloadManager
    private let nowPlaying = NowPlayingController()

    private var loadTask: Task<Void, Never>?
    private var itemTask: Task<Void, Never>?
    private var itemStatusObserver: AnyCancellable?
    private var timeObserver: Any?
    private var notificationObservers: [NSObjectProtocol] = []
    private var shouldResumeAfterInterruption = false

    init(history: PlaybackHistoryStore, downloads: DownloadManager) {
        self.history = history
        self.downloads = downloads

        player.publisher(for: \.timeControlStatus)
            .map { $0 == .playing }
            .removeDuplicates()
            .assign(to: &$isPlaying)

        configureAudioSession()
        observeAudioInterruptions()
        wireRemoteCommands()
        observePlaybackProgress()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Loading

    func load(videoID: String) {
        // A downloaded copy plays instantly and works offline, so it wins over streaming.
        let localURL = downloads.localURL(for: videoID)

        // Already showing this video in the right mode — but do switch over if it
        // has been downloaded since it started streaming.
        if videoID == self.videoID, (localURL != nil) == isPlayingLocalFile {
            return
        }

        loadTask?.cancel()
        resetPlaybackState()
        self.videoID = videoID
        state = .loading

        history.recordPlay(videoID: videoID)

        if let localURL {
            playLocalFile(at: localURL, videoID: videoID)
            return
        }

        let methods = extractionMethods
        loadTask = Task { [weak self] in
            await self?.performLoad(videoID: videoID, methods: methods)
        }
    }

    /// Plays the on-disk MP4. No extraction, no metadata fetch — the title comes
    /// from history so this path works with no network at all.
    private func playLocalFile(at url: URL, videoID: String) {
        isPlayingLocalFile = true
        isLive = false
        qualities = []
        selectedQualityID = nil

        if let entry = history.entries.first(where: { $0.id == videoID }) {
            title = entry.title
            thumbnailURL = entry.thumbnailURL
        }

        state = .ready
        install(AVPlayerItem(url: url), resumeAt: .zero, shouldResume: true)
    }

    /// The source the downloader should export, i.e. whatever quality is on screen.
    var downloadableSource: StreamResolver.Source? {
        guard !isPlayingLocalFile, let id = selectedQualityID else { return nil }
        return qualities.first(where: { $0.id == id })?.source
    }

    /// Re-resolves the current video — stream URLs are IP-bound and expire after a few hours.
    func reload() {
        guard let videoID else { return }
        self.videoID = nil
        load(videoID: videoID)
    }

    private var extractionMethods: [YouTube.ExtractionMethod] {
        usesRemoteFallback ? [.local, .remote] : [.local]
    }

    private func performLoad(videoID: String, methods: [YouTube.ExtractionMethod]) async {
        let video = YouTube(videoID: videoID, methods: methods)

        do {
            let (qualities, isLive) = try await StreamResolver.qualities(for: video)
            guard !Task.isCancelled, self.videoID == videoID else { return }

            guard let best = qualities.first else {
                state = .failed(StreamResolver.ResolverError.noPlayableStream.localizedDescription)
                return
            }

            self.qualities = qualities
            self.isLive = isLive
            self.state = .ready
            select(best, preservingPosition: false)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.videoID == videoID else { return }
            state = .failed(Self.message(for: error))
            return
        }

        // Metadata is a nice-to-have; a failure here must not break playback.
        guard let metadata = try? await video.metadata,
              !Task.isCancelled, self.videoID == videoID else { return }

        title = metadata.title
        thumbnailURL = metadata.thumbnail?.url ?? HistoryEntry.defaultThumbnailURL(for: videoID)
        history.updateDetails(videoID: videoID, title: title, thumbnailURL: thumbnailURL)
        updateNowPlaying()
    }

    private static func message(for error: Error) -> String {
        if let error = error as? YouTubeKitError {
            return error.errorDescription ?? "Couldn't extract this video (\(error.rawValue))."
        }
        return error.localizedDescription
    }

    // MARK: - Quality selection

    func select(_ quality: Quality) {
        select(quality, preservingPosition: true)
    }

    /// Building an adaptive item needs a network round trip to read track metadata,
    /// so item construction is async and cancellable.
    private func select(_ quality: Quality, preservingPosition: Bool) {
        guard selectedQualityID != quality.id || player.currentItem == nil else { return }
        selectedQualityID = quality.id

        let resumeAt = preservingPosition ? player.currentTime() : .zero
        let shouldResume = preservingPosition ? isPlaying : true

        itemTask?.cancel()
        itemTask = Task { [weak self] in
            guard let self else { return }
            do {
                let item = try await StreamResolver.makePlayerItem(for: quality.source)
                guard !Task.isCancelled, self.selectedQualityID == quality.id else { return }
                self.install(item, resumeAt: resumeAt, shouldResume: shouldResume)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.state = .failed(Self.message(for: error))
            }
        }
    }

    private func install(_ item: AVPlayerItem, resumeAt: CMTime, shouldResume: Bool) {
        observeFailure(of: item)
        player.replaceCurrentItem(with: item)

        if resumeAt.isValid, resumeAt.seconds > 0 {
            player.seek(to: resumeAt, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if shouldResume { player.play() }
        updateNowPlaying()
    }

    /// Surfaces decode/network failures on the item, which arrive asynchronously
    /// and would otherwise leave the player silently stuck on a black frame.
    private func observeFailure(of item: AVPlayerItem) {
        itemStatusObserver = item.publisher(for: \.status)
            .filter { $0 == .failed }
            .sink { [weak self, weak item] _ in
                guard let self, let item else { return }
                let reason = item.error?.localizedDescription ?? "Playback failed."
                Task { @MainActor in self.state = .failed(reason) }
            }
    }

    // MARK: - Transport

    func play() {
        player.play()
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        updateNowPlaying()
    }

    func stop() {
        player.pause()
        player.seek(to: .zero)
        updateNowPlaying()
    }

    func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlaying()
    }

    /// Clears everything except the audio-session/remote-command wiring, which is global.
    func resetPlaybackState() {
        loadTask?.cancel()
        loadTask = nil
        itemTask?.cancel()
        itemTask = nil
        itemStatusObserver = nil
        player.replaceCurrentItem(with: nil)
        state = .idle
        videoID = nil
        title = nil
        thumbnailURL = nil
        qualities = []
        selectedQualityID = nil
        isLive = false
        isPlayingLocalFile = false
        nowPlaying.clear()
    }

    // MARK: - Now Playing

    private func wireRemoteCommands() {
        nowPlaying.onPlay = { [weak self] in self?.play() }
        nowPlaying.onPause = { [weak self] in self?.pause() }
        nowPlaying.onStop = { [weak self] in self?.stop() }
        nowPlaying.onSeek = { [weak self] time in self?.seek(to: time) }
        nowPlaying.onTogglePlayPause = { [weak self] in
            guard let self else { return }
            isPlaying ? pause() : play()
        }
    }

    /// Keeps the lock-screen scrubber honest while the app is backgrounded.
    private func observePlaybackProgress() {
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateNowPlaying() }
        }
    }

    private func updateNowPlaying() {
        guard videoID != nil else { return }
        let duration = player.currentItem?.duration.seconds
        nowPlaying.update(
            title: title ?? videoID ?? "YouTube video",
            thumbnailURL: thumbnailURL ?? videoID.flatMap(HistoryEntry.defaultThumbnailURL),
            duration: (duration?.isFinite ?? false) ? duration : nil,
            elapsed: player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0,
            rate: player.rate,
            isLive: isLive
        )
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: playback still works, it just won't survive backgrounding.
        }
    }

    /// Pauses for phone calls and similar, and resumes when the system says we may.
    private func observeAudioInterruptions() {
        let observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleInterruption(notification) }
        }
        notificationObservers.append(observer)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            shouldResumeAfterInterruption = isPlaying
            player.pause()
        case .ended:
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume), shouldResumeAfterInterruption {
                try? AVAudioSession.sharedInstance().setActive(true)
                player.play()
            }
            shouldResumeAfterInterruption = false
        @unknown default:
            break
        }
    }
}
