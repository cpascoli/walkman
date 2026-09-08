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
            case .local: return "Taped"
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
            .navigationTitle("Tape Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .searchable(text: $query, prompt: "Search tapes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Clear Library", systemImage: "trash", role: .destructive) {
                            store.clear()
                        }
                        .disabled(store.entries.isEmpty)

                        Button("Erase All Tapes", systemImage: "internaldrive", role: .destructive) {
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
                "Library empty",
                icon: "tray",
                message: "Tapes you play will be filed here."
            )
        } else if visible.isEmpty, filter == .local {
            unavailable(
                "No tapes recorded",
                icon: "recordingtape",
                message: "Taped videos play straight off the device, with no network needed."
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
                    .legendStyle()
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
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .swipeActions(edge: .trailing) {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        downloads.delete(videoID: entry.id)
                        store.remove(entry)
                    }

                    if downloads.isDownloaded(entry.id) {
                        Button("Erase Tape", systemImage: "internaldrive") {
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
        HStack(spacing: 0) {
            thumbnail
            spine
            cassetteLabel
        }
        .frame(height: 74)
        .background(Theme.recess)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.black.opacity(0.7), lineWidth: 1)
        )
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    /// The narrow coloured band down the side of a cassette insert.
    private var spine: some View {
        Rectangle()
            .fill(isDownloaded ? Theme.accent : Color(white: 0.28))
            .frame(width: 4)
    }

    /// The paper label: title on the ruled line, details beneath.
    private var cassetteLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(Color(white: 0.12))

            Rectangle()
                .fill(Color(white: 0.12).opacity(0.25))
                .frame(height: 0.5)

            HStack(spacing: 5) {
                if isDownloaded {
                    Image(systemName: "recordingtape")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.62, green: 0.24, blue: 0.04))
                        .accessibilityLabel("Taped")
                }

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.12).opacity(0.65))
                    .lineLimit(1)
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
                Image(systemName: "photo")
                    .foregroundStyle(Theme.secondaryText)
            case .empty:
                ProgressView().controlSize(.small).tint(Theme.secondaryText)
            @unknown default:
                Color.clear
            }
        }
        .frame(width: 96, height: 74)
        .clipped()
        .background(Color(white: 0.1))
    }
}
