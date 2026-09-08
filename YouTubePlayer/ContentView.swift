import SwiftUI

/// The device front panel: brand plate, tape window, transport keys, and the
/// source controls tucked below like the switches on the side of a real deck.
struct ContentView: View {

    @ObservedObject var history: PlaybackHistoryStore
    @ObservedObject var nativeModel: NativePlayerModel
    @ObservedObject var downloads: DownloadManager
    @ObservedObject var queue: PlayQueue

    @State private var videoInput: String = ""
    @State private var embeddedVideoID: String?
    @State private var engine: PlaybackEngine = .native
    @State private var errorMessage: String?
    @State private var isShowingHistory = false

    @StateObject private var webCoordinator = PlayerCoordinator()
    @State private var embeddedAdvanceTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private var currentVideoID: String? {
        engine == .embedded ? embeddedVideoID : nativeModel.videoID
    }

    private var isPlaying: Bool {
        engine == .embedded ? webCoordinator.isPlaying : nativeModel.isPlaying
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
                    sourcePanel
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .sheet(isPresented: $isShowingHistory) {
            HistoryView(store: history, downloads: downloads) { entry in
                videoInput = entry.id
                play(videoID: entry.id)
            }
        }
        .onAppear {
            webCoordinator.onEnded = advanceEmbedded
        }
        .onChange(of: engine) { _, _ in
            embeddedAdvanceTask?.cancel()
            // Only one engine should ever be producing audio.
            webCoordinator.stop()
            nativeModel.pause()

            if let id = embeddedVideoID ?? nativeModel.videoID {
                play(videoID: id)
            }
        }
    }

    // MARK: - Face plate

    private var facePlate: some View {
        HStack(spacing: 12) {
            CaseScrew()

            VStack(alignment: .leading, spacing: 2) {
                Wordmark(text: "WALKMAN")
                Text("Personal Video Player")
                    .legendStyle()
            }

            Spacer(minLength: 0)

            IndicatorLamp(isLit: isPlaying)

            Button {
                isShowingHistory = true
            } label: {
                Image(systemName: "tray.full")
                    .font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(DeckKeyStyle(width: 46, height: 34))
            .accessibilityIdentifier("historyButton")
            .accessibilityLabel("Tape library")

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
                switch engine {
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

            tapeDeckStrip
        }
        .padding(10)
        .raisedPanel(cornerRadius: 10)
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
        HStack(spacing: 14) {
            DeckKey(legend: "Stop", action: stop) {
                Image(systemName: "stop.fill")
            }
            .accessibilityLabel("Stop")

            DeckKey(
                legend: isPlaying ? "Pause" : "Play",
                width: 86,
                tint: isPlaying ? Theme.accent : Theme.primaryText,
                action: togglePlayback
            ) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
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

    // MARK: - Source panel

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $nativeModel.isContinuousPlayEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Continuous play")
                        .legendStyle()
                    Text("Roll on through the library, 2s between tapes")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)

            Divider().overlay(Color.black.opacity(0.6))

            Text("Source")
                .legendStyle()

            Picker("Playback engine", selection: $engine) {
                ForEach(PlaybackEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            Text(engine.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)

            if engine == .native {
                Divider().overlay(Color.black.opacity(0.6))

                Toggle(isOn: $nativeModel.usesRemoteFallback) {
                    Text("Remote extraction fallback")
                        .legendStyle()
                }
                .tint(Theme.accent)
                .onChange(of: nativeModel.usesRemoteFallback) { _, _ in
                    nativeModel.reload()
                }
            }
        }
        .padding(14)
        .raisedPanel()
    }

    // MARK: - Actions

    private func loadFromInput() {
        // Get the keyboard out of the way; it covers the transport keys.
        isInputFocused = false

        guard let id = YouTubeVideoID.parse(videoInput) else {
            errorMessage = "Invalid YouTube URL or video ID"
            return
        }
        play(videoID: id)
    }

    private func play(videoID: String) {
        errorMessage = nil
        switch engine {
        case .embedded:
            if videoID != embeddedVideoID {
                queue.rebuild(from: history.entries, startingAt: videoID)
            }
            embeddedVideoID = videoID
            history.recordPlay(videoID: videoID)
            history.resolveDetailsIfNeeded(videoID: videoID)
        case .native:
            nativeModel.load(videoID: videoID)
        }
    }

    /// The embedded engine has no queue of its own, so it borrows the shared one.
    private func advanceEmbedded() {
        guard engine == .embedded, nativeModel.isContinuousPlayEnabled, queue.count > 0 else { return }

        embeddedAdvanceTask?.cancel()
        embeddedAdvanceTask = Task {
            try? await Task.sleep(for: NativePlayerModel.gapBetweenTapes)
            guard !Task.isCancelled, let next = queue.advance() else { return }

            if next == embeddedVideoID {
                webCoordinator.play()
            } else {
                play(videoID: next)
            }
        }
    }

    private func togglePlayback() {
        switch engine {
        case .embedded:
            isPlaying ? webCoordinator.pause() : webCoordinator.play()
        case .native:
            isPlaying ? nativeModel.pause() : nativeModel.play()
        }
    }

    private func stop() {
        embeddedAdvanceTask?.cancel()
        switch engine {
        case .embedded: webCoordinator.stop()
        case .native: nativeModel.stop()
        }
    }
}
