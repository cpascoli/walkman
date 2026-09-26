import SwiftUI

/// One recording, drawn as a cassette insert: artwork, coloured spine, paper label.
struct CassetteRow: View {

    let entry: HistoryEntry
    let isDownloaded: Bool
    /// Track number, shown when the row sits on a tape.
    var trackNumber: Int?

    var body: some View {
        HStack(spacing: 0) {
            thumbnail
            spine
            label
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

    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let trackNumber {
                    Text("\(trackNumber).")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.12).opacity(0.55))
                }

                Text(entry.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color(white: 0.12))
            }

            Rectangle()
                .fill(Color(white: 0.12).opacity(0.25))
                .frame(height: 0.5)

            HStack(spacing: 5) {
                if isDownloaded {
                    Image(systemName: "recordingtape")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.62, green: 0.24, blue: 0.04))
                        .accessibilityLabel("On device")
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
        // Filed from search and never played.
        guard entry.playCount > 0 else { return "Not played yet" }
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
