import SwiftUI

@main
struct WalkmanApp: App {

    @StateObject private var history: PlaybackHistoryStore
    @StateObject private var downloads: DownloadManager
    @StateObject private var queue: PlayQueue
    @StateObject private var library: TapeLibrary
    @StateObject private var nativeModel: NativePlayerModel

    init() {
        let history = PlaybackHistoryStore()
        let downloads = DownloadManager()
        let queue = PlayQueue()
        let library = TapeLibrary()

        // Lets the UI test suite start from a known-empty state. Must cover
        // every store, or tests leak state into each other.
        if ProcessInfo.processInfo.arguments.contains("-resetState") {
            history.clear()
            downloads.deleteAll()
            library.deleteAll()
        }
        _history = StateObject(wrappedValue: history)
        _downloads = StateObject(wrappedValue: downloads)
        _queue = StateObject(wrappedValue: queue)
        _library = StateObject(wrappedValue: library)
        _nativeModel = StateObject(wrappedValue: NativePlayerModel(history: history, downloads: downloads, queue: queue))

        // Thumbnails are re-requested constantly by the history list; give them
        // a real on-disk cache so the list renders instantly and works offline.
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView(history: history, nativeModel: nativeModel, downloads: downloads, queue: queue, library: library)
        }
    }
}
