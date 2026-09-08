import Foundation

/// The two ways this app can play a video.
enum PlaybackEngine: String, CaseIterable, Identifiable {
    /// YouTube's IFrame player inside a `WKWebView`.
    case embedded
    /// A direct stream URL resolved by YouTubeKit, played by `AVPlayer`.
    case native

    var id: String { rawValue }

    var title: String {
        switch self {
        case .embedded: return "Embedded"
        case .native: return "Native"
        }
    }

    var subtitle: String {
        switch self {
        case .embedded: return "YouTube IFrame player in a web view. No background playback."
        case .native: return "Direct stream via YouTubeKit + AVPlayer. Plays in the background."
        }
    }
}
