import SwiftUI

/// The device front panel: brand plate, tape window, transport keys, and the
/// source controls tucked below like the switches on the side of a real deck.
struct ContentView: View {

    @ObservedObject var history: PlaybackHistoryStore
    @ObservedObject var nativeModel: NativePlayerModel
    @ObservedObject var downloads: DownloadManager
    @ObservedObject var queue: PlayQueue
    @ObservedObject var library: TapeLibrary

    @State private var videoInput: String = ""
    @State private var embeddedVideoID: String?
    /// The player the user picked in Settings.
    @State private var engine: PlaybackEngine = .native
    /// The player actually driving playback. A recording with a local copy is
    /// always handed to the native player, whatever the setting says, so it
    /// keeps going in the background.
    @State private var activeEngine: PlaybackEngine = .native
    @State private var errorMessage: String?
    @State private var isShowingLibrary = false
    @State private var isShowingSettings = false

    @StateObject private var webCoordinator = PlayerCoordinator()
    @State private var embeddedAdvanceTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private var currentVideoID: String? {
        activeEngine == .embedded ? embeddedVideoID : nativeModel.videoID
    }

    private var isPlaying: Bool {
        activeEngine == .embedded ? webCoordinator.isPlaying : nativeModel.isPlaying
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    facePlate
                    loadSlot
                    tapeWindow
                    transportDeck
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .sheet(isPresented: $isShowingLibrary) {
            LibraryView(store: history, library: library, downloads: downloads) { request in
                videoInput = request.videoID
                play(request)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(model: nativeModel, downloads: downloads, engine: $engine)
        }
        .onAppear {
            webCoordinator.onEnded = advanceEmbedded
            nativeModel.onHandOff = { playQueued($0) }
            nativeModel.playsOnlyLocalCopies = engine == .embedded
        }
        .onChange(of: engine) { _, newEngine in
            embeddedAdvanceTask?.cancel()
            nativeModel.playsOnlyLocalCopies = newEngine == .embedded
            // Only one engine should ever be producing audio.
            webCoordinator.stop()
            nativeModel.pause()

            if let id = embeddedVideoID ?? nativeModel.videoID {
                playQueued(id)
            }
        }
    }

    // MARK: - Face plate

    private var facePlate: some View {
        HStack(spacing: 12) {
            CaseScrew()

            VStack(alignment: .leading, spacing: 2) {
                Wordmark(text: "WALKMAN")
                Text("Personal Video")
                    .legendStyle()
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            IndicatorLamp(isLit: isPlaying)

            Button {
                isShowingLibrary = true
            } label: {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(DeckKeyStyle(width: 44, height: 34))
            .accessibilityIdentifier("libraryButton")
            .accessibilityLabel("Tape library")

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(DeckKeyStyle(width: 44, height: 34))
            .accessibilityIdentifier("settingsButton")
            .accessibilityLabel("Settings")

            CaseScrew()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.darkMetal, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.highlight, .clear, Color.black.opacity(0.6)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Load slot

    private var loadSlot: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Load — URL or Video ID")
                .legendStyle()

            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $videoInput,
                    prompt: Text("dQw4w9WgXcQ").foregroundColor(Theme.secondaryText)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit(loadFromInput)
                .focused($isInputFocused)
                .accessibilityIdentifier("videoInput")
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Theme.label)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .recessedWell(cornerRadius: 4)

                Button("Load", action: loadFromInput)
                    .buttonStyle(DeckKeyStyle(width: 66, height: 44, tint: Theme.accent))
                    .accessibilityIdentifier("playButton")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("errorMessage")
            }
        }
        .padding(14)
        .raisedPanel()
    }

    // MARK: - Tape window

    private var tapeWindow: some View {
        VStack(spacing: 0) {
            Group {
                switch activeEngine {
                case .embedded:
                    if let embeddedVideoID {
                        YouTubePlayerView(videoId: embeddedVideoID, coordinator: webCoordinator)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    } else {
                        emptyBay
                    }
                case .native:
                    if nativeModel.videoID != nil {
                        NativePlayerView(model: nativeModel, downloads: downloads)
                    } else {
                        emptyBay
                    }
                }
            }
            .padding(8)
            .recessedWell(cornerRadius: 8)

            tapeReadout
            tapeDeckStrip
        }
        .padding(10)
        .raisedPanel(cornerRadius: 10)
    }

    /// Which tape is loaded and where we are on it.
    @ViewBuilder
    private var tapeReadout: some View {
        if queue.count > 0, !queue.sourceName.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 10))
                Text(queue.sourceName)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(queue.position)/\(queue.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .legendStyle()
            .padding(.horizontal, 6)
            .padding(.top, 10)
        }
    }

    /// The reels and counter below the window, as on a cassette door.
    private var tapeDeckStrip: some View {
        HStack {
            TapeTransport(isRunning: isPlaying)

            if nativeModel.isChangingTape {
                HStack(spacing: 6) {
                    IndicatorLamp(isLit: true, color: Theme.accent, diameter: 6)
                    Text("Changing tape")
                        .legendStyle()
                }
                .padding(.leading, 10)
            }

            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                TapeCounter(seconds: nativeModel.elapsed)
                Text("Counter")
                    .legendStyle()
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
    }

    private var emptyBay: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.slash")
                .font(.system(size: 30, weight: .light))
            Text("No tape loaded")
                .legendStyle()
        }
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }

    // MARK: - Transport

    private var transportDeck: some View {
        HStack(spacing: 10) {
            DeckKey(legend: "Rew", width: 52, action: skipBackward) {
                Image(systemName: "backward.end.fill")
            }
            .accessibilityLabel("Previous track")
            .accessibilityIdentifier("previousButton")

            DeckKey(legend: "Stop", width: 52, action: stop) {
                Image(systemName: "stop.fill")
            }
            .accessibilityLabel("Stop")

            DeckKey(
                legend: isPlaying ? "Pause" : "Play",
                width: 78,
                tint: isPlaying ? Theme.accent : Theme.primaryText,
                action: togglePlayback
            ) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            DeckKey(legend: "FF", width: 52, action: skipForward) {
                Image(systemName: "forward.end.fill")
            }
            .accessibilityLabel("Next track")
            .accessibilityIdentifier("nextButton")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.darkMetal, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(Color.black.opacity(0.7), lineWidth: 1)
        )
        .opacity(currentVideoID == nil ? 0.45 : 1)
        .disabled(currentVideoID == nil)
    }

    // MARK: - Actions

    private func loadFromInput() {
        // Get the keyboard out of the way; it covers the transport keys.
        isInputFocused = false

        guard let id = YouTubeVideoID.parse(videoInput) else {
            errorMessage = "Invalid YouTube URL or video ID"
            return
        }

        // A typed ID plays against the whole catalogue.
        play(
            PlaybackRequest(
                videoID: id,
                running: [id] + history.entries.map(\.id).filter { $0 != id },
                sourceName: "All Recordings"
            )
        )
    }

    private func play(_ request: PlaybackRequest) {
        errorMessage = nil

        // A local copy always goes to the native player: the web view can't
        // reach the file, and it can't keep playing once the app is backgrounded.
        let resolved = resolvedEngine(for: request.videoID)
        activeEngine = resolved

        switch resolved {
        case .embedded:
            webCoordinator.stop()
            queue.rebuild(from: request)
            playEmbedded(request.videoID)
        case .native:
            if engine == .embedded {
                // Handing off from the web view — silence it first.
                webCoordinator.stop()
                embeddedVideoID = nil
            }
            nativeModel.load(request)
        }
    }

    private func resolvedEngine(for videoID: String) -> PlaybackEngine {
        downloads.isDownloaded(videoID) ? .native : engine
    }

    /// Plays whatever the queue has landed on, re-resolving the engine so a
    /// downloaded track mid-tape still gets the native player.
    private func playQueued(_ videoID: String) {
        play(
            PlaybackRequest(
                videoID: videoID,
                running: queue.ids.isEmpty ? [videoID] : queue.ids,
                sourceName: queue.sourceName
            )
        )
    }

    private func playEmbedded(_ videoID: String) {
        embeddedVideoID = videoID
        history.recordPlay(videoID: videoID)
        history.resolveDetailsIfNeeded(videoID: videoID)
    }

    private func skipForward() {
        switch activeEngine {
        case .embedded:
            embeddedAdvanceTask?.cancel()
            if let next = queue.advance() { playQueued(next) }
        case .native:
            nativeModel.skipForward()
        }
    }

    private func skipBackward() {
        switch activeEngine {
        case .embedded:
            embeddedAdvanceTask?.cancel()
            if let previous = queue.previous() { playQueued(previous) }
        case .native:
            nativeModel.skipBackward()
        }
    }

    /// The embedded engine has no queue of its own, so it borrows the shared one.
    private func advanceEmbedded() {
        guard activeEngine == .embedded, nativeModel.isContinuousPlayEnabled, queue.count > 0 else { return }

        embeddedAdvanceTask?.cancel()
        embeddedAdvanceTask = Task {
            try? await Task.sleep(for: NativePlayerModel.gapBetweenTapes)
            guard !Task.isCancelled, let next = queue.advance() else { return }

            if next == embeddedVideoID {
                webCoordinator.play()
            } else {
                playQueued(next)
            }
        }
    }

    private func togglePlayback() {
        switch activeEngine {
        case .embedded:
            isPlaying ? webCoordinator.pause() : webCoordinator.play()
        case .native:
            isPlaying ? nativeModel.pause() : nativeModel.play()
        }
    }

    private func stop() {
        embeddedAdvanceTask?.cancel()
        switch activeEngine {
        case .embedded: webCoordinator.stop()
        case .native: nativeModel.stop()
        }
    }
}
