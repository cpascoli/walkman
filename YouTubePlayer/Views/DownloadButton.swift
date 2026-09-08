import SwiftUI

/// Compact download control reflecting `DownloadManager.Status` for one video.
struct DownloadButton: View {

    @ObservedObject var downloads: DownloadManager
    let videoID: String
    let source: StreamResolver.Source?

    var body: some View {
        switch downloads.status(for: videoID) {
        case .notDownloaded:
            Button {
                guard let source else { return }
                downloads.download(videoID: videoID, source: source)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .tint(Theme.primaryText)
            .disabled(source == nil)
            .accessibilityIdentifier("downloadButton")

        case .preparing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing…")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)

        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(width: 90)

                Text(progress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)

                Button("Cancel", systemImage: "xmark.circle.fill") {
                    downloads.cancel(videoID: videoID)
                }
                .labelStyle(.iconOnly)
                .tint(Theme.secondaryText)
            }

        case .downloaded:
            Menu {
                Button("Delete Download", systemImage: "trash", role: .destructive) {
                    downloads.delete(videoID: videoID)
                }
            } label: {
                Label(downloadedLabel, systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .accessibilityIdentifier("downloadedBadge")

        case .failed(let message):
            Button {
                guard let source else { return }
                downloads.cancel(videoID: videoID)
                downloads.download(videoID: videoID, source: source)
            } label: {
                Label("Retry", systemImage: "exclamationmark.arrow.circlepath")
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .help(message)
        }
    }

    private var downloadedLabel: String {
        guard let bytes = downloads.fileSize(for: videoID) else { return "Downloaded" }
        return "Saved · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
}
