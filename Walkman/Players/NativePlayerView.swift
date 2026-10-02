import SwiftUI

/// Presents the `AVPlayer` driven by `NativePlayerModel`, plus its load/quality chrome.
struct NativePlayerView: View {

    @ObservedObject var model: NativePlayerModel
    @ObservedObject var downloads: DownloadManager
    /// Shown in place of the picture. Without a video layer attached there's
    /// nothing to decode, and the audio plays on regardless.
    var cassette: CassetteView?
    /// The quality and download row under the picture; left out of the landscape view.
    var showsDetails = true

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if let cassette {
                    CassetteBay { cassette }
                } else {
                    ZStack {
                        Color.black
                        VideoSurface(player: model.player)
                    }
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                }

                switch model.state {
                case .loading:
                    ProgressView("Cueing tape…")
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.label)
                        .padding()
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                case .failed(let message):
                    failureOverlay(message)
                case .idle, .ready:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))

            if showsDetails, model.state == .ready {
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
            // The cassette label already carries the title.
            if cassette == nil, let title = model.title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if model.isLive {
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.led)
                } else if model.isPlayingLocalFile {
                    Label("Playing local copy", systemImage: "internaldrive")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityIdentifier("localPlaybackBadge")
                } else if model.qualities.count > 1 {
                    Picker("Quality", selection: qualitySelection) {
                        ForEach(model.qualities) { quality in
                            Text(quality.label).tag(quality.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.primaryText)

                    if model.isUpgradingQuality {
                        // Playing a quick low-quality stream until this one is ready.
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.secondaryText)
                            .accessibilityIdentifier("upgradingQuality")
                    }
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
