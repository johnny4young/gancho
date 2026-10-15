import Foundation
import GanchoKit
import Observation

public enum LibraryClipScope: Sendable, Equatable {
    case allClips, pinned
    case board(UUID)
    case savedFilter(SmartCollectionRule)
}

/// Owns the Library's browse requests, independently from the snippet draft.
/// Reloads retain the loaded window; cancelled or superseded reads cannot
/// publish rows, claim EOF, or dismiss a newer request's loading state.
@MainActor @Observable public final class LibraryClipListModel {
    public enum Failure: Sendable, Equatable { case unavailable, invalidFilter }
    public typealias Fetch = @MainActor (LibraryClipScope, Int, Int) async throws -> [ClipItem]

    public private(set) var items: [ClipItem] = []
    public private(set) var scope: LibraryClipScope = .allClips
    public private(set) var isLoading = false
    public private(set) var reachedEnd = false
    public private(set) var failure: Failure?
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var failedPage = false

    public init(fetch: @escaping Fetch) { self.fetch = fetch }

    public func cancel() {
        generation = UUID()
        isLoading = false
    }

    public func reload(_ scope: LibraryClipScope, preservingWindow: Bool = false) async {
        guard !Task.isCancelled else { return }
        let preserve = preservingWindow && scope == self.scope
        let count = preserve ? max(items.count, LibraryPager.pageSize) : LibraryPager.pageSize
        cancel()
        let request = generation
        self.scope = scope
        failure = nil
        failedPage = false
        reachedEnd = false
        if !preserve { items = [] }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        if case .savedFilter(let rule) = scope {
            await loadFilter(rule, request: request)
            return
        }
        let outcome = await page(loaded: [], size: count, scope: scope)
        apply(outcome, request: request)
    }

    public func loadMore() async {
        guard !Task.isCancelled, !isLoading, !reachedEnd else { return }
        let request = UUID()
        generation = request
        isLoading = true
        failure = nil
        failedPage = true
        defer { if generation == request { isLoading = false } }
        let outcome = await page(loaded: items, size: LibraryPager.pageSize, scope: scope)
        apply(outcome, request: request)
    }

    public func retry() async {
        if failedPage {
            await loadMore()
        } else {
            await reload(scope, preservingWindow: true)
        }
    }

    private func page(
        loaded: [ClipItem], size: Int, scope: LibraryClipScope
    ) async -> LibraryPager.Outcome {
        await LibraryPager.nextPage(
            loaded: loaded, pageSize: size,
            stopAt: scope == .pinned ? { !$0.isPinned } : nil
        ) { offset, limit in
            try await self.fetch(scope, offset, limit)
        }
    }

    private func apply(_ outcome: LibraryPager.Outcome, request: UUID) {
        guard generation == request, !Task.isCancelled else { return }
        switch outcome {
        case .loaded(let rows, let ended):
            items = rows
            reachedEnd = ended
        case .failed:
            failure = .unavailable
        }
    }

    private func loadFilter(_ rule: SmartCollectionRule, request: UUID) async {
        do {
            let matches = try await fetch(
                .savedFilter(rule), 0, (rule.textContains ?? "").isEmpty ? 500 : 100)
            guard generation == request, !Task.isCancelled else { return }
            let ranked =
                !(rule.textContains ?? "").isEmpty || rule.kinds != nil
                || rule.sourceAppBundleID != nil || rule.pinnedOnly
            items = ranked ? FrecencyRanker.reranked(matches) : matches
            reachedEnd = true
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            failure =
                error is SavedFilterError || error is ClipSearchError
                ? .invalidFilter : .unavailable
            reachedEnd = true
        }
    }
}
