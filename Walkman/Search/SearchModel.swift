import Foundation

/// Drives the search sheet: one query at a time, with paging.
@MainActor
final class SearchModel: ObservableObject {

    @Published var query = ""
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// The query the current results belong to, which may differ from what's typed.
    @Published private(set) var submittedQuery = ""

    private var continuation: String?
    private var task: Task<Void, Never>?
    private let client: YouTubeSearch

    init(client: YouTubeSearch = YouTubeSearch()) {
        self.client = client
    }

    var canLoadMore: Bool { continuation != nil && !isLoading }

    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        submittedQuery = trimmed
        results = []
        continuation = nil
        run { try await $0.search(trimmed) }
    }

    func loadMore() {
        guard canLoadMore, let continuation else { return }
        run { try await $0.more(after: continuation) }
    }

    private func run(_ fetch: @escaping (YouTubeSearch) async throws -> SearchPage) {
        // A new search supersedes whatever was in flight.
        task?.cancel()
        isLoading = true
        errorMessage = nil

        task = Task { [client] in
            do {
                let page = try await fetch(client)
                guard !Task.isCancelled else { return }
                let known = Set(results.map(\.id))
                results += page.results.filter { !known.contains($0.id) }
                continuation = page.results.isEmpty ? nil : page.continuation
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
