import SwiftUI

/// The tape library: your own tapes at the top, then the whole catalogue.
struct LibraryView: View {

    @ObservedObject var store: PlaybackHistoryStore
    @ObservedObject var library: TapeLibrary
    @ObservedObject var downloads: DownloadManager
    /// For downloading a whole tape, whose videos mostly aren't playing.
    let resolveDownload: DownloadManager.SourceResolver
    let onSelect: (PlaybackRequest) -> Void

    @State private var isNamingTape = false
    @State private var newTapeName = ""

    private var downloadedEntries: [HistoryEntry] {
        store.entries.filter { downloads.isDownloaded($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                tapesSection
                catalogueSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Tape Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Tape", systemImage: "plus") { beginNamingTape() }
                        .accessibilityIdentifier("newTapeButton")
                }
            }
            .alert("New Tape", isPresented: $isNamingTape) {
                TextField("Name", text: $newTapeName)
                    .accessibilityIdentifier("tapeNameField")
                Button("Create") { library.create(name: newTapeName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Name this tape.")
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var tapesSection: some View {
        Section {
            if library.tapes.isEmpty {
                Text("No tapes yet. Create one, then add recordings to it from All Recordings.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(library.tapes) { tape in
                    NavigationLink {
                        TapeDetailView(
                            tape: tape,
                            store: store,
                            library: library,
                            downloads: downloads,
                            resolveDownload: resolveDownload,
                            onSelect: select
                        )
                    } label: {
                        shelfRow(
                            title: tape.name,
                            detail: "\(tape.trackCount) track\(tape.trackCount == 1 ? "" : "s")",
                            icon: "rectangle.stack"
                        )
                    }
                    .accessibilityIdentifier("tapeRow_\(tape.name)")
                }
                .onDelete { library.delete(atOffsets: $0) }
            }
        } header: {
            Text("Tapes").legendStyle()
        }
        .listRowBackground(Theme.surface)
    }

    private var catalogueSection: some View {
        Section {
            NavigationLink {
                RecordingsListView(
                    title: "All Recordings",
                    entries: store.entries,
                    store: store,
                    library: library,
                    downloads: downloads,
                    onSelect: select
                )
            } label: {
                shelfRow(
                    title: "All Recordings",
                    detail: "\(store.entries.count)",
                    icon: "square.stack"
                )
            }
            .accessibilityIdentifier("allRecordingsRow")

            NavigationLink {
                RecordingsListView(
                    title: "On Device",
                    entries: downloadedEntries,
                    store: store,
                    library: library,
                    downloads: downloads,
                    onSelect: select
                )
            } label: {
                shelfRow(
                    title: "On Device",
                    detail: ByteCountFormatter.string(fromByteCount: downloads.totalBytesOnDisk, countStyle: .file),
                    icon: "recordingtape"
                )
            }
            .accessibilityIdentifier("tapedRow")
        } header: {
            Text("Catalogue").legendStyle()
        }
        .listRowBackground(Theme.surface)
    }

    private func shelfRow(title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.primaryText)

            Spacer()

            Text(detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 4)
    }

    private func beginNamingTape() {
        newTapeName = "Tape \(library.tapes.count + 1)"
        isNamingTape = true
    }

    private func select(_ request: PlaybackRequest) {
        onSelect(request)
    }
}

// MARK: - Tape contents

/// The tracks on one tape, in running order.
struct TapeDetailView: View {

    let tape: Tape
    @ObservedObject var store: PlaybackHistoryStore
    @ObservedObject var library: TapeLibrary
    @ObservedObject var downloads: DownloadManager
    let resolveDownload: DownloadManager.SourceResolver
    let onSelect: (PlaybackRequest) -> Void

    @State private var isRenaming = false
    @State private var draftName = ""
    @StateObject private var audioExport = AudioExport()
    @StateObject private var extender = TapeExtensionModel()

    /// The live tape, so edits made here are reflected immediately.
    private var current: Tape {
        library.tape(withID: tape.id) ?? tape
    }

    private var tracks: [HistoryEntry] {
        current.videoIDs.compactMap { id in
            store.entries.first { $0.id == id }
        }
    }

    /// Tracks not yet on the device.
    private var notDownloaded: [String] {
        current.videoIDs.filter { !downloads.isDownloaded($0) }
    }

    /// Whether this tape's tracks are among those being downloaded.
    private var isDownloadingTape: Bool {
        downloads.batch.contains { current.contains($0) }
    }

    var body: some View {
        List {
            if isDownloadingTape || failedDownloads > 0 {
                downloadRow
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)
            }

            if tracks.isEmpty {
                Text("This tape is empty. Add recordings from All Recordings.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .listRowBackground(Theme.background)
            } else {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { position, entry in
                    Button {
                        onSelect(
                            PlaybackRequest(
                                videoID: entry.id,
                                running: current.videoIDs,
                                sourceName: current.name
                            )
                        )
                    } label: {
                        CassetteRow(
                            entry: entry,
                            isDownloaded: downloads.isDownloaded(entry.id),
                            trackNumber: position + 1
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trackRow_\(entry.id)")
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .swipeActions(edge: .trailing) {
                        Button("Remove", systemImage: "minus.circle", role: .destructive) {
                            library.remove(entry.id, from: current)
                        }
                        exportAudioButton(for: entry, downloads: downloads, export: audioExport)
                    }
                }
                .onMove { library.moveTracks(in: current, fromOffsets: $0, toOffset: $1) }
                // Still what Edit mode's delete buttons use.
                .onDelete { library.removeTracks(in: current, atOffsets: $0) }

                extendRow
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .presentingAudioExport(audioExport)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        draftName = current.name
                        isRenaming = true
                    }
                    if isDownloadingTape {
                        Button("Stop Downloading", systemImage: "stop.circle") {
                            downloads.cancelBatch()
                        }
                    } else if !notDownloaded.isEmpty {
                        Button(downloadAllTitle, systemImage: "arrow.down.circle") {
                            downloads.downloadAll(notDownloaded, resolve: resolveDownload)
                        }
                        .accessibilityIdentifier("downloadTapeButton")
                    }
                    if !tracks.isEmpty {
                        EditButton()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("tapeMenu")
            }
        }
        .alert("Rename Tape", isPresented: $isRenaming) {
            TextField("Name", text: $draftName)
            Button("Save") { library.rename(current, to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Downloading

    private var downloadAllTitle: String {
        notDownloaded.count == current.videoIDs.count
            ? "Download All"
            : "Download Remaining \(notDownloaded.count)"
    }

    /// Tracks whose last download attempt failed and that still aren't saved.
    private var failedDownloads: Int {
        notDownloaded.filter {
            if case .failed = downloads.status(for: $0) { true } else { false }
        }.count
    }

    /// Progress through a tape download, at the top while it runs; afterwards,
    /// how many couldn't be saved.
    private var downloadRow: some View {
        let saved = current.videoIDs.count - notDownloaded.count
        let currentID = downloads.batch.first { current.contains($0) }
        let title = currentID.flatMap { id in store.entries.first { $0.id == id }?.title }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isDownloadingTape {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.secondaryText)
                    Text("Downloading · \(saved) of \(current.videoIDs.count) on device")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.accent)
                    Text("\(failedDownloads) couldn't be downloaded. Use Download Remaining to try again.")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)

            if let currentID, let title {
                HStack(spacing: 8) {
                    Text(title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if case .downloading(let progress) = downloads.status(for: currentID) {
                        Text(progress.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                    } else {
                        Text("Cueing…")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tapeDownloadStatus")
    }

    // MARK: - More like this

    /// At the foot of the tape: more tracks like the last one, from Last.fm.
    private var extendRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch extender.phase {
            case .identifying, .findingSimilar, .searchingYouTube:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Theme.secondaryText)
                    Text(extendProgressText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("extendTapeProgress")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityIdentifier("extendTapeError")
                extendButton
            case .added(let count, let seed):
                Text(count == 0
                     ? "Everything like \(seed.artist) — \(seed.name) is already on this tape."
                     : "Added \(count) track\(count == 1 ? "" : "s") like \(seed.artist) — \(seed.name).")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("extendTapeResult")
                extendButton
            case .idle:
                extendButton
            }
        }
        .padding(.vertical, 12)
    }

    private var extendButton: some View {
        Button(action: extendTape) {
            VStack(spacing: 3) {
                Label("Add \(SimilarTapeModel.trackCount) More Like This", systemImage: "rectangle.stack.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                if let last = tracks.last {
                    Text("Similar to “\(last.title)”")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .tint(Theme.accent)
        .accessibilityIdentifier("extendTapeButton")
    }

    private var extendProgressText: String {
        switch extender.phase {
        case .identifying: "Working out what the last track is…"
        case .findingSimilar: "Asking Last.fm for similar tracks…"
        case .searchingYouTube(let done, let total): "Finding them on YouTube · \(done) of \(total)"
        case .idle, .added, .failed: ""
        }
    }

    private func extendTape() {
        guard let last = tracks.last else { return }
        extender.extend(from: last, skipping: current.videoIDs) { found in
            for video in found {
                store.file(video)
            }
            library.add(found.map(\.id), to: current)
        }
    }
}

// MARK: - Recordings

/// A flat, searchable list of recordings.
struct RecordingsListView: View {

    let title: String
    let entries: [HistoryEntry]
    @ObservedObject var store: PlaybackHistoryStore
    @ObservedObject var library: TapeLibrary
    @ObservedObject var downloads: DownloadManager
    let onSelect: (PlaybackRequest) -> Void

    @State private var query = ""
    @State private var pendingTapeVideoID: String?
    @State private var newTapeName = ""
    @StateObject private var audioExport = AudioExport()

    private var visible: [HistoryEntry] {
        entries.filter { $0.matches(query) }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Nothing here yet", systemImage: "tray")
                } description: {
                    Text("Recordings you play are filed here automatically.")
                }
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                list
            }
        }
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(text: $query, prompt: "Search recordings")
        .alert("New Tape", isPresented: .init(
            get: { pendingTapeVideoID != nil },
            set: { if !$0 { pendingTapeVideoID = nil } }
        )) {
            TextField("Name", text: $newTapeName)
            Button("Create") {
                if let id = pendingTapeVideoID {
                    library.create(name: newTapeName, videoIDs: [id])
                }
                pendingTapeVideoID = nil
            }
            Button("Cancel", role: .cancel) { pendingTapeVideoID = nil }
        }
    }

    private var list: some View {
        List {
            ForEach(visible) { entry in
                Button {
                    // The visible order is what plays on, so a filtered list
                    // rolls through exactly what the user can see.
                    onSelect(
                        PlaybackRequest(
                            videoID: entry.id,
                            running: visible.map(\.id),
                            sourceName: title
                        )
                    )
                } label: {
                    CassetteRow(entry: entry, isDownloaded: downloads.isDownloaded(entry.id))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recordingRow_\(entry.id)")
                .listRowBackground(Theme.background)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .contextMenu { tapeMenu(for: entry) }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        downloads.delete(videoID: entry.id)
                        library.purge(entry.id)
                        store.remove(entry)
                    }

                    if downloads.isDownloaded(entry.id) {
                        Button("Delete Local Copy", systemImage: "recordingtape") {
                            downloads.delete(videoID: entry.id)
                        }
                        .tint(.orange)
                    }

                    exportAudioButton(for: entry, downloads: downloads, export: audioExport)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .presentingAudioExport(audioExport)
    }

    @ViewBuilder
    private func tapeMenu(for entry: HistoryEntry) -> some View {
        Menu("Add to Tape", systemImage: "rectangle.stack.badge.plus") {
            ForEach(library.tapes) { tape in
                Button {
                    library.toggle(entry.id, on: tape)
                } label: {
                    Label(tape.name, systemImage: tape.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                }
            }

            Divider()

            Button("New Tape…", systemImage: "plus") {
                newTapeName = "Tape \(library.tapes.count + 1)"
                pendingTapeVideoID = entry.id
            }
        }
    }
}

// MARK: - Exporting audio

/// The swipe action that exports a recording's audio — only for recordings
/// with a copy on the device.
@ViewBuilder
@MainActor
private func exportAudioButton(for entry: HistoryEntry, downloads: DownloadManager, export: AudioExport) -> some View {
    if let file = downloads.localURL(for: entry.id) {
        Button("Export Audio", systemImage: "square.and.arrow.up") {
            export.export(entry, from: file)
        }
        .tint(.blue)
    }
}
