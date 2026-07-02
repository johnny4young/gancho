import Foundation
import GanchoAI
import GanchoKit

/// Suggests which existing board a freshly captured clip most likely belongs
/// to, by a semantic k-nearest-neighbors vote over how the user has already
/// filed similar clips. This is the single home for the logic both app shells
/// used to inline byte-for-byte (`AppModel`/`IOSAppModel.suggestedBoard`).
///
/// The app shells keep only their platform pre-gate (the `intelligence.autoBoard`
/// user toggle and the concrete-store downcast); everything reachable through
/// the store facets lives here so it is `swift test`-able for the first time.
///
/// Stateless and `Sendable`: it constructs a `ContextualSentenceEmbedder`
/// per call exactly as the inlined code did, touches only the async store and
/// the pure `BoardSuggester` vote, and never crosses an actor boundary with a
/// non-`Sendable` value — so it needs no `@MainActor` isolation. On CI the
/// embedder reports `hasAvailableAssets == false`, so the semantic path yields
/// nil there; the pre-embedder guards remain unit-testable.
public struct BoardSuggestionService: Sendable {
    public init() {}

    /// The board this clip probably belongs to, or nil when the clip is
    /// sensitive, there are no eligible user boards, the embedder has no
    /// on-device assets, or the neighborhood shows no clear home. 100%
    /// on-device; only ever suggests (never files).
    ///
    /// - Parameters:
    ///   - item: the clip to place.
    ///   - store: the capability surface — reading, searching, and boards.
    public func suggest(
        for item: ClipItem,
        store: any BoardStoring & ClipReading & ClipSearching
    ) async -> Pinboard? {
        guard !item.isSensitive else { return nil }
        let userBoards = ((try? await store.pinboards()) ?? []).filter { !$0.isSystem }
        guard !userBoards.isEmpty else { return nil }
        let current = (try? await store.boardIDs(forClip: item.id)) ?? []
        let candidates = Set(userBoards.map(\.id)).subtracting(current)
        guard !candidates.isEmpty else { return nil }

        guard case .text(let text)? = try? await store.content(for: item.id),
            let embedder = ContextualSentenceEmbedder(), embedder.hasAvailableAssets,
            let vector = try? embedder.vector(for: String(text.prefix(1_000)))
        else { return nil }
        let neighbors =
            ((try? await store.semanticSearch(
                queryVector: vector, topK: 8, snippetsOnly: false)) ?? [])
            .filter { $0.id != item.id }
        guard !neighbors.isEmpty else { return nil }

        var neighborBoards: [Set<UUID>] = []
        for neighbor in neighbors {
            neighborBoards.append((try? await store.boardIDs(forClip: neighbor.id)) ?? [])
        }
        guard
            let vote = BoardSuggester.suggest(
                neighborBoardIDs: neighborBoards, candidates: candidates)
        else { return nil }
        return userBoards.first { $0.id == vote.boardID }
    }
}
