import SwiftUI

@main
struct YouTubePlayerApp: App {

    @StateObject private var history: PlaybackHistoryStore
    @StateObject private var downloads: DownloadManager
    @StateObject private var queue: PlayQueue
    @StateObject private var nativeModel: NativePlayerModel

    init() {
        let history = PlaybackHistoryStore()
        let downloads = DownloadManager()
        let queue = PlayQueue()

        // Lets the UI test suite start from a known-empty state.
        if ProcessInfo.processInfo.arguments.contains("-resetState") {
            history.clear()
            downloads.deleteAll()
        }
        _history = StateObject(wrappedValue: history)
        _downloads = StateObject(wrappedValue: downloads)
        _queue = StateObject(wrappedValue: queue)
        _nativeModel = StateObject(wrappedValue: NativePlayerModel(history: history, downloads: downloads, queue: queue))

        // Thumbnails are re-requested constantly by the history list; give them
        // a real on-disk cache so the list renders instantly and works offline.
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(history: history, nativeModel: nativeModel, downloads: downloads, queue: queue)
        }
    }
}
