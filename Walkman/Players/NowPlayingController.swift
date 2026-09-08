import AVFoundation
import MediaPlayer
import UIKit

/// Publishes playback state to the lock screen / Control Center and routes the
/// remote transport commands back to the player.
///
/// This is what makes backgrounded playback controllable once the app's own UI is gone.
@MainActor
final class NowPlayingController {

    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onSeek: ((TimeInterval) -> Void)?

    private var artworkTask: Task<Void, Never>?
    private var artworkSourceURL: URL?
    private var artwork: MPMediaItemArtwork?

    init() {
        registerCommands()
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.onStop?()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.onSeek?(event.positionTime)
            return .success
        }
    }

    /// Set by the model so the toggle command can consult current playback state.
    var onTogglePlayPause: (() -> Void)?

    /// Pushes the current track and playback position to the system.
    func update(title: String, thumbnailURL: URL?, duration: TimeInterval?, elapsed: TimeInterval, rate: Float, isLive: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyIsLiveStream: isLive,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]

        if let duration, duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkIfNeeded(from: thumbnailURL)

        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.isEnabled = !isLive
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkSourceURL = nil
        artwork = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// Downloads the thumbnail once per video and re-publishes the info dictionary with it.
    private func loadArtworkIfNeeded(from url: URL?) {
        guard let url, url != artworkSourceURL else { return }
        artworkSourceURL = url
        artwork = nil

        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  !Task.isCancelled else { return }

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            guard let self, self.artworkSourceURL == url else { return }
            self.artwork = artwork

            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
    }
}
