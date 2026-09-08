import SwiftUI

/// Searchable list of previously played videos; selecting one hands its ID back to the player.
struct HistoryView: View {

    /// Which slice of the history is on screen.
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case local

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .local: return "Local"
            }
        }
    }

    @ObservedObject var store: PlaybackHistoryStore
    @ObservedObject var downloads: DownloadManager
    let onSelect: (HistoryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter: Filter = .all

    private var visible: [HistoryEntry] {
        store.entries(matching: query).filter {
            filter == .all || downloads.isDownloaded($0.id)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("historyFilter")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                    content
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $query, prompt: "Search by title or video ID")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Clear History", systemImage: "trash", role: .destructive) {
                            store.clear()
                        }
                        .disabled(store.entries.isEmpty)

                        Button("Delete All Downloads", systemImage: "internaldrive", role: .destructive) {
                            downloads.deleteAll()
                        }
                        .disabled(downloads.downloadedIDs.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if store.entries.isEmpty {
            unavailable(
                "No history yet",
                icon: "clock.arrow.circlepath",
                message: "Videos you play will appear here."
            )
        } else if visible.isEmpty, filter == .local {
            unavailable(
                "No downloads",
                icon: "internaldrive",
                message: "Downloaded videos play from the device, with no network needed."
            )
        } else if visible.isEmpty {
            unavailable(
                "No results",
                icon: "magnifyingglass",
                message: "No video matches “\(query)”."
            )
        } else {
            list
        }
    }

    private func unavailable(_ title: String, icon: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        List {
            if filter == .local, !downloads.downloadedIDs.isEmpty {
                Text("\(ByteCountFormatter.string(fromByteCount: downloads.totalBytesOnDisk, countStyle: .file)) on device")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .listRowBackground(Theme.background)
                    .listRowSeparator(.hidden)
            }

            ForEach(visible) { entry in
                Button {
                    onSelect(entry)
                    dismiss()
                } label: {
                    HistoryRow(entry: entry, isDownloaded: downloads.isDownloaded(entry.id))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("historyRow_\(entry.id)")
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.border)
                .swipeActions(edge: .trailing) {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        downloads.delete(videoID: entry.id)
                        store.remove(entry)
                    }

                    if downloads.isDownloaded(entry.id) {
                        Button("Delete Download", systemImage: "internaldrive") {
                            downloads.delete(videoID: entry.id)
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }
}

private struct HistoryRow: View {

    let entry: HistoryEntry
    let isDownloaded: Bool

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(Theme.primaryText)

                HStack(spacing: 6) {
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Downloaded")
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let relative = entry.lastPlayedAt.formatted(.relative(presentation: .named))
        return entry.playCount > 1 ? "\(relative) · \(entry.playCount) plays" : relative
    }

    private var thumbnail: some View {
        AsyncImage(url: entry.thumbnailURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "play.rectangle")
                    .foregroundStyle(Theme.secondaryText)
            case .empty:
                ProgressView().controlSize(.small)
            @unknown default:
                Color.clear
            }
        }
        .frame(width: 106, height: 60)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomTrailing) {
            if isDownloaded {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.65), in: Circle())
                    .padding(4)
            }
        }
    }
}
