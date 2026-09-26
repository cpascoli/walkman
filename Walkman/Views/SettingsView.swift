import SwiftUI

/// Deck settings, kept off the main panel so the player stays uncluttered.
struct SettingsView: View {

    @ObservedObject var model: NativePlayerModel
    @ObservedObject var downloads: DownloadManager
    @Binding var engine: PlaybackEngine

    @State private var isConfirmingErase = false
    @State private var lastFMKey = LastFMCredentials.storedKey

    var body: some View {
        NavigationStack {
            Form {
                playbackSection
                engineSection
                lastFMSection
                storageSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var playbackSection: some View {
        Section {
            Toggle("Continuous play", isOn: $model.isContinuousPlayEnabled)
                .tint(Theme.accent)
        } header: {
            Text("Playback").legendStyle()
        } footer: {
            Text("Roll on through the tape when a track ends, with a 2 second gap between tracks. Wraps around at the end.")
        }
        .listRowBackground(Theme.surface)
    }

    private var engineSection: some View {
        Section {
            Picker("Player", selection: $engine) {
                ForEach(PlaybackEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            Text(engine.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)

            if engine == .native {
                Toggle("Remote extraction fallback", isOn: $model.usesRemoteFallback)
                    .tint(Theme.accent)
                    .onChange(of: model.usesRemoteFallback) { _, _ in
                        model.reload()
                    }
            }
        } header: {
            Text("Player").legendStyle()
        } footer: {
            if engine == .native {
                Text("If YouTube changes its API and local extraction breaks, fall back to YouTubeKit's remote extractor. Costs a round trip.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var lastFMSection: some View {
        Section {
            TextField("API key", text: $lastFMKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 13, design: .monospaced))
                .onChange(of: lastFMKey) { _, key in LastFMCredentials.save(key) }
                .accessibilityIdentifier("lastFMKeyField")
        } header: {
            Text("Last.fm").legendStyle()
        } footer: {
            Text("Used to make tapes of similar tracks from a search result. Get a key by creating an API account at last.fm/api. Only the key is needed, not the shared secret. It's kept in the Keychain.")
        }
        .listRowBackground(Theme.surface)
    }

    private var storageSection: some View {
        Section {
            LabeledContent("Recordings on device") {
                Text("\(downloads.downloadedIDs.count)")
                    .foregroundStyle(Theme.secondaryText)
            }
            LabeledContent("Space used") {
                Text(ByteCountFormatter.string(fromByteCount: downloads.totalBytesOnDisk, countStyle: .file))
                    .foregroundStyle(Theme.secondaryText)
            }

            Button("Delete All Local Copies", role: .destructive) {
                isConfirmingErase = true
            }
            .disabled(downloads.downloadedIDs.isEmpty)
        } header: {
            Text("Storage").legendStyle()
        }
        .listRowBackground(Theme.surface)
        .confirmationDialog(
            "Delete every local copy?",
            isPresented: $isConfirmingErase,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { downloads.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recordings stay in your library and on your tapes, and will stream again.")
        }
    }
}
