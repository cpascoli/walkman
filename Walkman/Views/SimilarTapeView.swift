import SwiftUI

/// A draft tape of tracks like a search result, to review before saving:
/// rename it, drop what doesn't fit, reorder, and preview any track.
struct SimilarTapeView: View {

    @ObservedObject var store: PlaybackHistoryStore
    @ObservedObject var library: TapeLibrary
    let onPreviewStart: () -> Void

    @StateObject private var model: SimilarTapeModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hasEditedName = false

    init(
        original: SearchResult,
        store: PlaybackHistoryStore,
        library: TapeLibrary,
        onPreviewStart: @escaping () -> Void
    ) {
        self.store = store
        self.library = library
        self.onPreviewStart = onPreviewStart
        _model = StateObject(wrappedValue: SimilarTapeModel(original: original))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            nameSection

            if case .failed(let message) = model.phase {
                failure(message)
            } else {
                tracksSection
                missingSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("New Tape")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(model.isWorking || model.items.isEmpty || trimmedName.isEmpty)
                    .accessibilityIdentifier("saveSimilarTapeButton")
            }
            ToolbarItem(placement: .secondaryAction) {
                EditButton()
                    .disabled(model.isWorking)
            }
        }
        .onAppear(perform: model.start)
        .onChange(of: model.seed) { _, seed in
            // Name it after the song once Last.fm has said what it is, unless
            // the user got there first.
            guard let seed, !hasEditedName else { return }
            name = "Like \(seed.name)"
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Tape name", text: Binding(
                get: { name },
                set: { name = $0; hasEditedName = true }
            ))
            .font(.system(size: 15, weight: .semibold))
            .accessibilityIdentifier("similarTapeName")
        } header: {
            Text("Name").legendStyle()
        } footer: {
            if let seed = model.seed {
                Text("Tracks Last.fm finds similar to \(seed.artist) — \(seed.name).")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var tracksSection: some View {
        Section {
            // At the top, so it stays in view while tracks pile up below.
            if model.isWorking {
                progressRow
                    .listRowBackground(Theme.background)
            }

            ForEach(Array(model.items.enumerated()), id: \.element.id) { position, item in
                NavigationLink {
                    SearchResultDetailView(
                        result: item.video,
                        store: store,
                        library: library,
                        onPreviewStart: onPreviewStart,
                        allowsFiling: false
                    )
                } label: {
                    SearchResultRow(
                        result: item.video,
                        isFiled: store.contains(item.video.id),
                        note: note(for: item, position: position)
                    )
                }
                .accessibilityIdentifier("draftTrack_\(item.id)")
                .listRowBackground(Theme.background)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .onDelete(perform: model.remove)
            .onMove(perform: model.move)
        } header: {
            HStack {
                Text("Tracks").legendStyle()
                Spacer()
                Text("\(model.items.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("draftTrackCount")
            }
        } footer: {
            if !model.isWorking, !model.items.isEmpty {
                Text("Swipe to drop a track, or tap Edit to reorder. Tap one to preview it.")
            }
        }
    }

    @ViewBuilder
    private var missingSection: some View {
        if !model.missing.isEmpty {
            Section {
                ForEach(model.missing, id: \.self) { track in
                    Text("\(track.artist) — \(track.name)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text("Not found on YouTube").legendStyle()
            }
            .listRowBackground(Theme.surface)
        }
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Theme.secondaryText)
            Text(progressText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("similarTapeProgress")
    }

    private var progressText: String {
        switch model.phase {
        case .identifying: "Asking Last.fm what this song is…"
        case .findingSimilar: "Asking Last.fm for similar tracks…"
        case .searchingYouTube(let done, let total): "Finding them on YouTube · \(done) of \(total)"
        case .finished, .failed: ""
        }
    }

    private func failure(_ message: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                Button("Try Again", action: model.retry)
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("similarTapeError")
        }
        .listRowBackground(Theme.surface)
    }

    private func note(for item: SimilarTapeModel.Item, position: Int) -> String {
        guard let source = item.source else { return "The original" }
        let match = source.match.map { " · \(Int(($0 * 100).rounded()))% match" } ?? ""
        return "Last.fm: \(source.artist) — \(source.name)\(match)"
    }

    // MARK: - Saving

    private func save() {
        for item in model.items {
            store.file(item.video)
        }
        library.create(name: trimmedName, videoIDs: model.items.map(\.id))
        dismiss()
    }
}
