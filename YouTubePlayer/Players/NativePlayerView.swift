import SwiftUI

/// Presents the `AVPlayer` driven by `NativePlayerModel`, plus its load/quality chrome.
struct NativePlayerView: View {

    @ObservedObject var model: NativePlayerModel
    @ObservedObject var downloads: DownloadManager

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Color.black
                VideoSurface(player: model.player)

                switch model.state {
                case .loading:
                    ProgressView("Resolving stream…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                case .failed(let message):
                    failureOverlay(message)
                case .idle, .ready:
                    EmptyView()
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if model.state == .ready {
                details
            }
        }
    }

    private func failureOverlay(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("Try again") { model.reload() }
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding()
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = model.title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if model.isLive {
                    Label("Live stream", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                } else if model.isPlayingLocalFile {
                    Label("Playing downloaded file", systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("localPlaybackBadge")
                } else if model.qualities.count > 1 {
                    Picker("Quality", selection: qualitySelection) {
                        ForEach(model.qualities) { quality in
                            Text(quality.label).tag(quality.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.primaryText)
                } else if let only = model.qualities.first {
                    Text(only.label)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer(minLength: 0)

                if let videoID = model.videoID, !model.isLive {
                    DownloadButton(
                        downloads: downloads,
                        videoID: videoID,
                        source: model.downloadableSource
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var qualitySelection: Binding<Int> {
        Binding(
            get: { model.selectedQualityID ?? model.qualities.first?.id ?? 0 },
            set: { id in
                guard let quality = model.qualities.first(where: { $0.id == id }) else { return }
                model.select(quality)
            }
        )
    }
}
