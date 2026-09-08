import AVFoundation
import Foundation
import YouTubeKit

/// Turns a YouTube video into a set of playable qualities, and turns a chosen
/// quality into an `AVPlayerItem`.
///
/// YouTube only publishes muxed (video+audio in one file) streams up to 360p.
/// Everything above that is "adaptive": separate video-only and audio-only files.
/// To offer real quality options we stitch an adaptive pair back together in an
/// `AVMutableComposition`, which `AVPlayer` streams just like a single asset.
enum StreamResolver {

    enum Source: Hashable {
        /// A single muxed file — simplest, but capped at 360p by YouTube.
        case progressive(URL)
        /// Separate video-only and audio-only tracks, combined into a composition.
        case adaptive(video: URL, audio: URL)
        /// Live HLS manifest, which `AVPlayer` handles natively.
        case hls(URL)
    }

    struct Quality: Identifiable, Hashable {
        /// Vertical resolution, which also orders and uniquely identifies the option.
        let id: Int
        let label: String
        let source: Source
    }

    enum ResolverError: LocalizedError {
        case noPlayableStream

        var errorDescription: String? {
            "No natively playable stream is available for this video."
        }
    }

    // MARK: - Resolution

    static func qualities(for video: YouTube) async throws -> (qualities: [Quality], isLive: Bool) {
        var streams: [YouTubeKit.Stream] = []
        var hitLivestream = false

        do {
            streams = try await video.streams
        } catch YouTubeKitError.liveStreamError {
            hitLivestream = true
        }

        let qualities = buildQualities(from: streams)
        if !qualities.isEmpty {
            return (qualities, false)
        }

        if let hls = try await video.livestreams.first(where: { $0.streamType == .hls }) {
            return ([Quality(id: 0, label: "Live · auto", source: .hls(hls.url))], true)
        }

        if hitLivestream {
            throw YouTubeKitError.liveStreamError
        }
        throw ResolverError.noPlayableStream
    }

    /// Builds one option per available resolution, preferring adaptive pairs
    /// (which reach 1080p+) and filling in any resolution only progressive offers.
    private static func buildQualities(from streams: [YouTubeKit.Stream]) -> [Quality] {
        let playable = streams.filter { $0.isNativelyPlayable }

        // Highest-bitrate audio track to pair with every adaptive video track.
        let bestAudio = playable.filterAudioOnly()
            .max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }

        var byResolution: [Int: Source] = [:]

        if let audioURL = bestAudio?.url {
            for stream in playable.filterVideoOnly() {
                guard let resolution = stream.videoResolution else { continue }
                // Keep the first (highest-bitrate) track seen for each resolution.
                if byResolution[resolution] == nil {
                    byResolution[resolution] = .adaptive(video: stream.url, audio: audioURL)
                }
            }
        }

        for stream in playable.filterVideoAndAudio() {
            guard let resolution = stream.videoResolution else { continue }
            if byResolution[resolution] == nil {
                byResolution[resolution] = .progressive(stream.url)
            }
        }

        return byResolution
            .sorted { $0.key > $1.key }
            .map { Quality(id: $0.key, label: "\($0.key)p", source: $0.value) }
    }

    // MARK: - Player items

    @MainActor
    static func makePlayerItem(for source: Source) async throws -> AVPlayerItem {
        AVPlayerItem(asset: try await makeAsset(for: source))
    }

    /// The playable asset behind a quality — also what the downloader exports from.
    static func makeAsset(for source: Source) async throws -> AVAsset {
        switch source {
        case .progressive(let url), .hls(let url):
            return AVURLAsset(url: url)
        case .adaptive(let videoURL, let audioURL):
            return try await composition(video: videoURL, audio: audioURL)
        }
    }

    /// Streams a video-only and an audio-only URL as one asset. Only the track
    /// metadata is fetched up front; the media itself still streams on demand.
    private static func composition(video videoURL: URL, audio audioURL: URL) async throws -> AVComposition {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
        async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
        async let videoDuration = videoAsset.load(.duration)
        async let audioDuration = audioAsset.load(.duration)

        guard let videoTrack = try await videoTracks.first,
              let audioTrack = try await audioTracks.first else {
            throw ResolverError.noPlayableStream
        }

        let duration = try await min(videoDuration, audioDuration)
        let range = CMTimeRange(start: .zero, duration: duration)

        let composition = AVMutableComposition()
        if let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try track.insertTimeRange(range, of: videoTrack, at: .zero)
        }
        if let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try track.insertTimeRange(range, of: audioTrack, at: .zero)
        }

        return composition
    }
}
