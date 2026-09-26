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

        /// The length YouTube states in the stream URL's `dur` parameter.
        /// Trusted over the asset's own duration, which AVFoundation reads as
        /// double for YouTube's fragmented MP4s (see `makeAsset`).
        var statedDuration: TimeInterval? {
            let url: URL
            switch self {
            case .progressive(let progressive): url = progressive
            case .adaptive(let video, _): url = video
            case .hls: return nil
            }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "dur" }?.value
                .flatMap(TimeInterval.init)
        }
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

    /// Something that can start playing straight away while `best` is built.
    ///
    /// Building an adaptive composition means AVFoundation reads through much of
    /// the video file first, so the time grows with the file: about a second at
    /// 360p but over ten at 1080p. The smallest pair at 360p or above gets sound
    /// going while the real one is built. Nil when `best` is itself that quick.
    ///
    /// Not the muxed 360p file, which looks ideal but YouTube now refuses —
    /// AVFoundation takes a dozen seconds to give up on it.
    static func quickStart(from qualities: [Quality], below best: Quality) -> Source? {
        guard best.id > quickStartResolution, case .adaptive = best.source else { return nil }
        return qualities
            .filter { $0.id >= quickStartResolution && $0.id < best.id }
            .min { $0.id < $1.id }?
            .source
    }

    static let quickStartResolution = 360

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
    ///
    /// Cut to the length YouTube states. Its DASH files are fragmented MP4s
    /// whose header declares the whole length, and AVFoundation counts that on
    /// top of the fragments, so it reports double: a 19 second video comes out
    /// at 38, the second half silent and black. The fragments themselves are
    /// timed from zero, so cutting at the stated length loses nothing.
    static func makeAsset(for source: Source) async throws -> AVAsset {
        switch source {
        case .hls(let url):
            return AVURLAsset(url: url)
        case .progressive(let url):
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.load(.tracks)
            return try await composition(of: tracks, from: [asset], cutAt: source.statedDuration)
        case .adaptive(let videoURL, let audioURL):
            let videoAsset = AVURLAsset(url: videoURL)
            let audioAsset = AVURLAsset(url: audioURL)
            async let videoTracks = videoAsset.loadTracks(withMediaType: .video)
            async let audioTracks = audioAsset.loadTracks(withMediaType: .audio)
            guard let videoTrack = try await videoTracks.first,
                  let audioTrack = try await audioTracks.first else {
                throw ResolverError.noPlayableStream
            }
            return try await composition(of: [videoTrack, audioTrack], from: [videoAsset, audioAsset],
                                         cutAt: source.statedDuration)
        }
    }

    /// A recording on the device, cut to its shortest track.
    ///
    /// Recordings exported before streams were cut to length kept the doubled
    /// length on their video track, while the audio track ends where the
    /// samples do. Healthy recordings' tracks end together, so they play as is.
    static func makeLocalAsset(at url: URL) async throws -> AVAsset {
        let asset = AVURLAsset(url: url)
        async let tracks = asset.load(.tracks)
        async let duration = asset.load(.duration)
        let shortest = try await trackEnds(try await tracks).min() ?? .zero
        guard try await duration.seconds - shortest.seconds > 0.5 else { return asset }
        return try await composition(of: try await tracks, from: [asset], cutAt: nil)
    }

    /// The tracks as one asset, ending with the shortest of them — or sooner,
    /// at `length` seconds. Only the tracks' metadata is fetched up front; the
    /// media itself still streams on demand.
    ///
    /// A track holds its asset only weakly, so `assets` are kept alive until
    /// the tracks are copied: otherwise the copy fails with error -12780.
    private static func composition(of tracks: [AVAssetTrack], from assets: [AVAsset],
                                    cutAt length: TimeInterval?) async throws -> AVComposition {
        let composition = try await copy(tracks, cutAt: length)
        withExtendedLifetime(assets) {}
        return composition
    }

    private static func copy(_ tracks: [AVAssetTrack], cutAt length: TimeInterval?) async throws -> AVComposition {
        var end = try await trackEnds(tracks).min() ?? .zero
        if let length {
            end = CMTimeMinimum(end, CMTime(seconds: length, preferredTimescale: 600))
        }
        let range = CMTimeRange(start: .zero, end: end)

        let composition = AVMutableComposition()
        for track in tracks {
            guard let copy = composition.addMutableTrack(withMediaType: track.mediaType,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            try copy.insertTimeRange(range, of: track, at: .zero)
        }
        return composition
    }

    private static func trackEnds(_ tracks: [AVAssetTrack]) async throws -> [CMTime] {
        var ends: [CMTime] = []
        for track in tracks {
            ends.append(try await track.load(.timeRange).end)
        }
        return ends
    }
}
