import SwiftUI

/// Search YouTube, preview a result, and file it into the library.
struct SearchView: View {

    @ObservedObject var store: PlaybackHistoryStore
    @ObservedObject var library: TapeLibrary
    /// Called when a preview starts playing, so the deck can fall silent.
    let onPreviewStart: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SearchModel()
    @State private var pendingTapeResult: SearchResult?
    @State private var newTapeName = ""

    var body: some View {
        NavigationStack {
            content
                .background(Theme.background)
                .navigationTitle("Search YouTube")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.surface, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .searchable(
                    text: $model.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search YouTube"
                )
                .onSubmit(of: .search) { model.submit() }
                .navigationDestination(for: SearchResult.self) { result in
                    SearchResultDetailView(
                        result: result,
                        store: store,
                        library: library,
                        onPreviewStart: onPreviewStart
                    )
                }
                .alert("New Tape", isPresented: .init(
                    get: { pendingTapeResult != nil },
                    set: { if !$0 { pendingTapeResult = nil } }
                )) {
                    TextField("Name", text: $newTapeName)
                    Button("Create") {
                        if let result = pendingTapeResult {
                            store.file(result)
                            library.create(name: newTapeName, videoIDs: [result.id])
                        }
                        pendingTapeResult = nil
                    }
                    Button("Cancel", role: .cancel) { pendingTapeResult = nil }
                }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if model.results.isEmpty {
            if model.isLoading {
                ProgressView()
                    .tint(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.errorMessage {
                ContentUnavailableView {
                    Label("Search failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { model.submit() }
                }
            } else if model.submittedQuery.isEmpty {
                ContentUnavailableView {
                    Label("Find a tape", systemImage: "magnifyingglass")
                } description: {
                    Text("Search YouTube, preview what you find, and file it into your library.")
                }
            } else {
                ContentUnavailableView.search(text: model.submittedQuery)
            }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(model.results) { result in
                NavigationLink(value: result) {
                    SearchResultRow(result: result, isFiled: store.contains(result.id))
                }
                .accessibilityIdentifier("searchResultRow_\(result.id)")
                .listRowBackground(Theme.background)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .contextMenu { fileMenu(for: result) }
            }

            if model.canLoadMore || (model.isLoading && !model.results.isEmpty) {
                // Pages in as the end scrolls into view.
                ProgressView()
                    .tint(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)
                    .onAppear { model.loadMore() }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func fileMenu(for result: SearchResult) -> some View {
        Button("Add to All Recordings", systemImage: "square.stack") {
            store.file(result)
        }
        .disabled(store.contains(result.id))

        Menu("Add to Tape", systemImage: "rectangle.stack.badge.plus") {
            ForEach(library.tapes) { tape in
                Button {
                    toggle(result, on: tape, store: store, library: library)
                } label: {
                    Label(tape.name, systemImage: tape.contains(result.id) ? "checkmark.circle.fill" : "circle")
                }
            }

            Divider()

            Button("New Tape…", systemImage: "plus") {
                newTapeName = "Tape \(library.tapes.count + 1)"
                pendingTapeResult = result
            }
        }
    }
}

// MARK: - Result detail

/// A single result: a playable preview, its details, and where to file it.
struct SearchResultDetailView: View {

    let result: SearchResult
    @ObservedObject var store: PlaybackHistoryStore
    @ObservedObject var library: TapeLibrary
    let onPreviewStart: () -> Void
    /// Off when previewing a track on a draft tape, where filing it would
    /// sidestep the draft.
    var allowsFiling = true

    @StateObject private var preview = PreviewPlayerModel()
    @State private var isNamingTape = false
    @State private var newTapeName = ""

    private var isFiled: Bool { store.contains(result.id) }

    var body: some View {
        List {
            Section {
                previewPlayer
                    .padding(8)
                    .recessedWell(cornerRadius: 8)
                    .listRowBackground(Theme.background)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                details
                    .listRowBackground(Theme.background)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }

            if allowsFiling {
                similarTapeSection
                recordingsSection
                tapesSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: preview.isPlaying) { _, isPlaying in
            if isPlaying { onPreviewStart() }
        }
        .onAppear { preview.load(videoID: result.id) }
        .alert("New Tape", isPresented: $isNamingTape) {
            TextField("Name", text: $newTapeName)
            Button("Create") {
                store.file(result)
                library.create(name: newTapeName, videoIDs: [result.id])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name this tape. \(result.title) goes on it first.")
        }
    }

    /// Streams the video itself, so it plays in the app rather than in YouTube's
    /// embed, which refuses many videos. Waits for the user to press play.
    private var previewPlayer: some View {
        ZStack {
            Color.black
            VideoSurface(player: preview.player, allowsPictureInPicture: false)

            switch preview.state {
            case .loading:
                ProgressView("Cueing preview…")
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.label)
                    .padding()
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Try again") { preview.retry() }
                        .buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
                .padding()
            case .idle, .ready:
                EmptyView()
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityIdentifier("searchPreview")
        .overlay(alignment: .topTrailing) {
            if let quality = preview.qualityLabel {
                Text(quality)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 2))
                    .padding(6)
                    .accessibilityIdentifier("previewQuality")
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            Text(result.metadataLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)

            if !result.snippet.isEmpty {
                Text(result.snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText.opacity(0.8))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var similarTapeSection: some View {
        Section {
            NavigationLink {
                SimilarTapeView(
                    original: result,
                    store: store,
                    library: library,
                    onPreviewStart: onPreviewStart
                )
            } label: {
                Label("Tape of Similar Tracks", systemImage: "wand.and.stars")
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityIdentifier("similarTapeButton")
        } header: {
            Text("Make a Tape").legendStyle()
        } footer: {
            Text("Last.fm suggests \(SimilarTapeModel.trackCount) tracks like this one, each found on YouTube. You review the tape before saving it.")
        }
        .listRowBackground(Theme.surface)
    }

    private var recordingsSection: some View {
        Section {
            Button {
                store.file(result)
            } label: {
                Label(
                    isFiled ? "In All Recordings" : "Add to All Recordings",
                    systemImage: isFiled ? "checkmark.circle.fill" : "plus.circle"
                )
            }
            .disabled(isFiled)
            .accessibilityIdentifier("addToRecordingsButton")
        } header: {
            Text("Catalogue").legendStyle()
        }
        .listRowBackground(Theme.surface)
    }

    private var tapesSection: some View {
        Section {
            ForEach(library.tapes) { tape in
                Button {
                    toggle(result, on: tape, store: store, library: library)
                } label: {
                    HStack {
                        Image(systemName: tape.contains(result.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(Theme.accent)
                        Text(tape.name)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Text("\(tape.trackCount)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .accessibilityIdentifier("tapeToggle_\(tape.name)")
            }

            Button("New Tape…", systemImage: "plus") {
                newTapeName = "Tape \(library.tapes.count + 1)"
                isNamingTape = true
            }
            .accessibilityIdentifier("newTapeFromSearchButton")
        } header: {
            Text("Tapes").legendStyle()
        } footer: {
            Text("Putting it on a tape also files it in All Recordings.")
        }
        .listRowBackground(Theme.surface)
    }
}

// MARK: - Result row

/// A search result, drawn like the cassette inserts in the library.
struct SearchResultRow: View {

    let result: SearchResult
    /// Already in All Recordings.
    let isFiled: Bool
    /// Shown in place of the description, e.g. why it's on a draft tape.
    var note: String?

    var body: some View {
        HStack(spacing: 0) {
            thumbnail
            Rectangle()
                .fill(isFiled ? Theme.accent : Color(white: 0.28))
                .frame(width: 4)
            label
        }
        .frame(height: 96)
        .background(Theme.recess)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.black.opacity(0.7), lineWidth: 1)
        )
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(result.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(Color(white: 0.12))

            HStack(spacing: 5) {
                if isFiled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.62, green: 0.24, blue: 0.04))
                        .accessibilityLabel("In library")
                }
                Text(result.metadataLine)
                    .lineLimit(1)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(white: 0.12).opacity(0.65))

            if let text = note ?? (result.snippet.isEmpty ? nil : result.snippet) {
                Text(text)
                    .font(.system(size: 10))
                    .lineLimit(2)
                    .foregroundStyle(Color(white: 0.12).opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Theme.label, Theme.label.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var thumbnail: some View {
        AsyncImage(url: result.thumbnailURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "photo")
                    .foregroundStyle(Theme.secondaryText)
            case .empty:
                ProgressView().controlSize(.small).tint(Theme.secondaryText)
            @unknown default:
                Color.clear
            }
        }
        .frame(width: 112, height: 96)
        .clipped()
        .background(Color(white: 0.1))
        .overlay(alignment: .bottomTrailing) {
            if !result.duration.isEmpty {
                Text(result.duration)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 2))
                    .padding(4)
            }
        }
    }
}

// MARK: - Filing

extension SearchResult {
    /// Channel, length, views and age, as far as YouTube supplied them.
    var metadataLine: String {
        [channel, duration, viewCount, published]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

extension PlaybackHistoryStore {
    /// Files a search result into All Recordings.
    ///
    /// Stores YouTube's stable thumbnail rather than the one from the search
    /// response, whose URL is signed and not meant to be kept.
    func file(_ result: SearchResult) {
        add(videoID: result.id, title: result.title)
    }
}

/// Toggles a result on a tape. A tape only shows tracks that are in the
/// catalogue, so putting a result on one files it there too.
@MainActor
private func toggle(_ result: SearchResult, on tape: Tape, store: PlaybackHistoryStore, library: TapeLibrary) {
    if !tape.contains(result.id) { store.file(result) }
    library.toggle(result.id, on: tape)
}
