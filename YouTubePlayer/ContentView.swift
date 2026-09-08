import SwiftUI

struct ContentView: View {

    @ObservedObject var history: PlaybackHistoryStore
    @ObservedObject var nativeModel: NativePlayerModel
    @ObservedObject var downloads: DownloadManager

    @State private var videoInput: String = ""
    @State private var embeddedVideoID: String?
    @State private var engine: PlaybackEngine = .native
    @State private var errorMessage: String?
    @State private var isShowingHistory = false

    @StateObject private var webCoordinator = PlayerCoordinator()

    private var currentVideoID: String? {
        engine == .embedded ? embeddedVideoID : nativeModel.videoID
    }

    private var isPlaying: Bool {
        engine == .embedded ? webCoordinator.isPlaying : nativeModel.isPlaying
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        inputCard

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                                .accessibilityIdentifier("errorMessage")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        playerSection

                        if currentVideoID != nil {
                            transportControls
                        }

                        engineCard
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("MyTube Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("History", systemImage: "clock.arrow.circlepath") {
                        isShowingHistory = true
                    }
                    .accessibilityIdentifier("historyButton")
                    .tint(Theme.primaryText)
                }
            }
            .sheet(isPresented: $isShowingHistory) {
                HistoryView(store: history, downloads: downloads) { entry in
                    videoInput = entry.id
                    play(videoID: entry.id)
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onChange(of: engine) { _, _ in
            // Only one engine should ever be producing audio.
            webCoordinator.stop()
            nativeModel.pause()

            if let id = embeddedVideoID ?? nativeModel.videoID {
                play(videoID: id)
            }
        }
    }

    // MARK: - Sections

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YouTube URL or Video ID")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)

            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $videoInput,
                    prompt: Text("dQw4w9WgXcQ or a full URL").foregroundColor(Theme.secondaryText)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .submitLabel(.go)
                .onSubmit(loadFromInput)
                .accessibilityIdentifier("videoInput")
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))

                Button("Play", action: loadFromInput)
                    .accessibilityIdentifier("playButton")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .card()
    }

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Playback engine", selection: $engine) {
                ForEach(PlaybackEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            Text(engine.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            if engine == .native {
                Divider().overlay(Theme.border)

                Toggle(isOn: $nativeModel.usesRemoteFallback) {
                    Text("Remote extraction fallback")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .tint(Theme.accent)
                .onChange(of: nativeModel.usesRemoteFallback) { _, _ in
                    nativeModel.reload()
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private var playerSection: some View {
        switch engine {
        case .embedded:
            if let embeddedVideoID {
                YouTubePlayerView(videoId: embeddedVideoID, coordinator: webCoordinator)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            } else {
                placeholder
            }
        case .native:
            if nativeModel.videoID != nil {
                NativePlayerView(model: nativeModel, downloads: downloads)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 44, weight: .light))
            Text("No video loaded")
                .font(.callout)
        }
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.border, lineWidth: 1)
        )
    }

    private var transportControls: some View {
        HStack(spacing: 36) {
            Button(action: stop) {
                Image(systemName: "stop.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 58, height: 58)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel("Stop")

            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 4)
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func loadFromInput() {
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
            embeddedVideoID = videoID
            history.recordPlay(videoID: videoID)
            history.resolveDetailsIfNeeded(videoID: videoID)
        case .native:
            nativeModel.load(videoID: videoID)
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
        switch engine {
        case .embedded: webCoordinator.stop()
        case .native: nativeModel.stop()
        }
    }
}
