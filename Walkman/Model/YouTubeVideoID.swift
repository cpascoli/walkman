import Foundation

/// Parses YouTube video identifiers out of the many URL shapes YouTube uses,
/// or accepts a bare 11-character video ID.
enum YouTubeVideoID {

    /// Path prefixes that carry the video ID as the following path component.
    private static let idCarryingPathPrefixes = ["shorts", "embed", "live", "v"]

    /// Returns the video ID contained in `input`, or `nil` if there isn't a valid one.
    static func parse(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A bare ID is the common case and never contains a slash or dot.
        if isValid(trimmed) { return trimmed }

        // Tolerate URLs pasted without a scheme (e.g. "youtu.be/dQw4w9WgXcQ").
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate) else { return nil }

        guard let id = extract(from: components), isValid(id) else { return nil }
        return id
    }

    private static func extract(from components: URLComponents) -> String? {
        let host = components.host?.lowercased() ?? ""
        let segments = components.path.split(separator: "/").map(String.init)

        // youtu.be/<id>
        if host.hasSuffix("youtu.be") {
            return segments.first
        }

        guard host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") else {
            return nil
        }

        // youtube.com/watch?v=<id>
        if let v = components.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }

        // youtube.com/{shorts,embed,live,v}/<id>
        if let first = segments.first, idCarryingPathPrefixes.contains(first.lowercased()) {
            return segments.dropFirst().first
        }

        return nil
    }

    /// YouTube video IDs are exactly 11 URL-safe base64 characters.
    static func isValid(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }
}
