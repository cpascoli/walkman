import SwiftUI

/// The device front panel: brand plate, tape window, transport keys, and the
/// source controls tucked below like the switches on the side of a real deck.
/// The Player tab.
struct ContentView: View {

    @ObservedObject var history: PlaybackHistoryStore
    @ObservedObject var nativeModel: NativePlayerModel
    @ObservedObject var downloads: DownloadManager
    @ObservedObject var queue: PlayQueue
    @ObservedObject var library: TapeLibrary
    /// The player the user picked in Settings.
    @Binding var engine: PlaybackEngine
    /// Requests from the other tabs; handled, then cleared.
    @Binding var command: DeckCommand?
    /// Turned on its side: just the tape window, filling the screen — the
    /// cassette, or the picture when that's what's showing.
    var isImmersive = false

    @State private var videoInput: String = ""
    @State private var embeddedVideoID: String?
    /// The player actually driving playback. A recording with a local copy is
    /// always handed to the native player, whatever the setting says, so it
    /// keeps going in the background.
    @State private var activeEngine: PlaybackEngine = .native
    @State private var errorMessage: String?
    /// Shows the picture instead of the cassette.
    @AppStorage("showsVideo") private var showsVideo = false

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
            background.ignoresSafeArea()

            // Everything stays in one hierarchy in both orientations, with the
            // rest of the deck falling away around the tape window rather than
            // the window moving somewhere new: the players inside it would be
            // rebuilt, and the music would stop.
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        if !isImmersive {
                            facePlate
                            loadSlot
                        }
                        tapeWindow
                        if !isImmersive {
                            transportDeck
                        }
                    }
                    .padding(isImmersive ? 0 : 16)
                    .frame(height: isImmersive ? geometry.size.height : nil)
                }
                .scrollDisabled(isImmersive)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onChange(of: command) { _, command in
            guard let command else { return }
            self.command = nil
            switch command {
            case .play(let request):
                videoInput = request.videoID
                play(request)
            case .pause:
                pauseDeck()
            }
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

    private var background: Color {
        guard isImmersive else { return Theme.background }
        // Looking into the deck at the tape, or a screen showing the picture.
        return showsVideo && currentVideoID != nil ? .black : Theme.recess
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
                .padding(.trailing, 6)

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
                        ZStack {
                            // The web view has to stay in the hierarchy to keep
                            // playing, so the cassette covers it rather than replacing it.
                            YouTubePlayerView(videoId: embeddedVideoID, coordinator: webCoordinator)
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                            if !showsVideo {
                                CassetteBay { cassette(for: embeddedVideoID) }
                                    .background(Theme.recess)
                            }
                        }
                    } else {
                        emptyBay
                    }
                case .native:
                    if let videoID = nativeModel.videoID {
                        NativePlayerView(
                            model: nativeModel,
                            downloads: downloads,
                            cassette: showsVideo ? nil : cassette(for: videoID),
                            showsDetails: !isImmersive
                        )
                    } else {
                        emptyBay
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: isImmersive ? .infinity : nil)
            .overlay {
                if showsDeckGestures {
                    DeckGestures(
                        isPlaying: isPlaying,
                        position: activeEngine == .native ? counterReading : nil,
                        onTogglePlayback: togglePlayback,
                        onNextTrack: skipForward,
                        onRestart: restartTape,
                        onWind: wind
                    )
                }
            }
            .padding(isImmersive ? 0 : 8)
            .recessedWell(cornerRadius: 8, isShown: !isImmersive)

            if !isImmersive {
                tapeReadout
                tapeDeckStrip
            }
        }
        .padding(isImmersive ? 0 : 10)
        .raisedPanel(cornerRadius: 10, isShown: !isImmersive)
    }

    /// On its side, the cassette is the controls. Not over the picture, which
    /// has its own, nor over a failed load, whose retry button would be covered.
    private var showsDeckGestures: Bool {
        guard isImmersive, !showsVideo, currentVideoID != nil else { return false }
        if activeEngine == .native, case .failed = nativeModel.state { return false }
        return true
    }

    private var counterReading: String {
        Duration.seconds(nativeModel.elapsed).formatted(.time(pattern: .minuteSecond))
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
            VStack(spacing: 5) {
                Button {
                    showsVideo.toggle()
                } label: {
                    Image(systemName: showsVideo ? "recordingtape" : "play.rectangle")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(DeckKeyStyle(width: 44, height: 28))
                .accessibilityIdentifier("videoToggle")
                .accessibilityLabel(showsVideo ? "Show cassette" : "Show video")

                Text(showsVideo ? "Tape" : "Video")
                    .legendStyle()
            }
            .disabled(currentVideoID == nil)
            .opacity(currentVideoID == nil ? 0.45 : 1)

            // With the picture up, the reels live down here instead.
            if showsVideo {
                TapeTransport(isRunning: isPlaying)
                    .padding(.leading, 8)
            }

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

    /// The tape in the deck, labelled with whatever the catalogue knows about it.
    private func cassette(for videoID: String) -> CassetteView {
        let entry = history.entries.first { $0.id == videoID }
        let isNative = activeEngine == .native
        // An entry titled with its bare ID is still waiting for its details.
        let title = [entry?.title, isNative ? nativeModel.title : nil]
            .compactMap { $0 }
            .first { $0 != videoID } ?? videoID

        var progress: Double?
        var length: String?
        if isNative, !nativeModel.isLive, let duration = nativeModel.duration, duration > 0 {
            progress = nativeModel.elapsed / duration
            length = Duration.seconds(duration).formatted(.time(pattern: duration >= 3600 ? .hourMinuteSecond : .minuteSecond))
        }

        return CassetteView(
            title: title,
            thumbnailURL: entry?.thumbnailURL ?? HistoryEntry.defaultThumbnailURL(for: videoID),
            isRunning: isPlaying,
            progress: progress,
            length: length
        )
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

    /// Silences the deck without unloading it, e.g. while a search preview plays.
    private func pauseDeck() {
        embeddedAdvanceTask?.cancel()
        switch activeEngine {
        case .embedded: webCoordinator.pause()
        case .native: nativeModel.pause()
        }
    }

    private func restartTape() {
        switch activeEngine {
        case .embedded: webCoordinator.restart()
        case .native: nativeModel.seek(to: 0)
        }
    }

    private func wind(by seconds: TimeInterval) {
        switch activeEngine {
        case .embedded: webCoordinator.skip(by: seconds)
        case .native: nativeModel.skip(by: seconds)
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
