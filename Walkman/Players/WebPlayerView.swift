import SwiftUI
import WebKit

/// Drives the YouTube IFrame player inside a `WKWebView` and mirrors its state back to SwiftUI.
@MainActor
final class PlayerCoordinator: NSObject, ObservableObject {

    /// Reflects the IFrame player's own state, so the UI stays correct when the
    /// user drives playback from the embedded controls rather than our buttons.
    @Published private(set) var isPlaying = false

    /// Called when the embedded player reaches the end of the video.
    var onEnded: (() -> Void)?

    fileprivate weak var webView: WKWebView?
    fileprivate var loadedVideoID: String?

    func play() {
        evaluate("playVideo();")
    }

    func pause() {
        evaluate("pauseVideo();")
    }

    func stop() {
        evaluate("stopVideo();")
    }

    /// Jumps along the video; stops short of the end, as the native player does.
    func skip(by seconds: TimeInterval) {
        evaluate("skipBy(\(seconds));")
    }

    func restart() {
        evaluate("restartVideo();")
    }

    private func evaluate(_ javaScript: String) {
        webView?.evaluateJavaScript(javaScript, completionHandler: nil)
    }
}

extension PlayerCoordinator: WKScriptMessageHandler {

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "playerState", let state = message.body as? Int else { return }
        // YT.PlayerState: 1 == playing, 0 == ended
        isPlaying = (state == 1)
        if state == 0 { onEnded?() }
    }
}

struct YouTubePlayerView: UIViewRepresentable {

    let videoId: String
    let coordinator: PlayerCoordinator

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(coordinator, name: "playerState")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only when the video actually changes; SwiftUI may call this often.
        guard coordinator.loadedVideoID != videoId else { return }
        coordinator.loadedVideoID = videoId
        webView.loadHTMLString(html(for: videoId), baseURL: Self.origin)
    }

    /// The page's own origin. YouTube refuses to play (error 152) for an embed
    /// claiming to be youtube.com itself, or one with no origin at all.
    private static let origin = URL(string: "https://com.carlopascoli.walkman")!

    static func dismantleUIView(_ webView: WKWebView, coordinator: Void) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playerState")
        webView.loadHTMLString("", baseURL: nil)
    }

    private func html(for videoId: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                html, body { margin: 0; padding: 0; background-color: #000; overflow: hidden; height: 100%; }
                #player { width: 100%; height: 100%; }
            </style>
        </head>
        <body>
            <div id="player"></div>
            <script>
                var tag = document.createElement('script');
                tag.src = "https://www.youtube.com/iframe_api";
                document.head.appendChild(tag);

                var player;

                function onYouTubeIframeAPIReady() {
                    player = new YT.Player('player', {
                        height: '100%',
                        width: '100%',
                        videoId: '\(videoId)',
                        playerVars: {
                            'playsinline': 1,
                            'autoplay': 1,
                            'controls': 1,
                            'rel': 0,
                            'origin': '\(Self.origin.absoluteString)',
                            'modestbranding': 1
                        },
                        events: {
                            'onReady': function (event) { event.target.playVideo(); },
                            'onStateChange': function (event) { postState(event.data); }
                        }
                    });
                }

                function postState(state) {
                    window.webkit.messageHandlers.playerState.postMessage(state);
                }

                function playVideo() { if (player && player.playVideo) { player.playVideo(); } }
                function pauseVideo() { if (player && player.pauseVideo) { player.pauseVideo(); } }
                function skipBy(seconds) {
                    if (player && player.seekTo) {
                        var target = Math.max(0, player.getCurrentTime() + seconds);
                        var duration = player.getDuration();
                        if (duration > 1) { target = Math.min(target, duration - 1); }
                        player.seekTo(target, true);
                    }
                }
                function restartVideo() { if (player && player.seekTo) { player.seekTo(0, true); } }
                function stopVideo() {
                    if (player && player.stopVideo) {
                        player.stopVideo();
                        postState(-1);
                    }
                }
            </script>
        </body>
        </html>
        """
    }
}
