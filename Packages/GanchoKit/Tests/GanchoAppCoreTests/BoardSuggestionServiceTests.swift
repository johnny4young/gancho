import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// A recording fake store: it answers only the calls the pre-embedder guards
/// make and counts them, so a test can assert not just the returned value but
/// *how far the service got* before returning — that's what makes the guard
/// tests non-vacuous on CI, where `ContextualSentenceEmbedder` reports no
/// on-device assets and the semantic tail can never produce a positive result.
private actor FakeStore: BoardStoring, ClipReading, ClipSearching {
    let boards: [Pinboard]
    private(set) var pinboardsCalls = 0
    private(set) var boardIDsCalls = 0
    private(set) var contentCalls = 0

    init(boards: [Pinboard]) { self.boards = boards }

    // BoardStoring — only these three are reachable before the embedder.
    func pinboards() async throws -> [Pinboard] {
        pinboardsCalls += 1
        return boards
    }
    func boardIDs(forClip clipID: UUID) async throws -> Set<UUID> {
        boardIDsCalls += 1
        return []
    }

    // ClipReading — `content(for:)` is the last hop before the embedder guard.
    func content(for id: UUID) async throws -> ClipContent? {
        contentCalls += 1
        return nil
    }

    // Remaining requirements are never exercised by these tests; they return
    // trivial values so the fake conforms.
    func createPinboard(name: String, sfSymbol: String) async throws -> Pinboard {
        Pinboard(name: name, sfSymbol: sfSymbol)
    }
    func renameBoard(id: UUID, name: String) async throws {}
    func updateBoardIdentity(id: UUID, colorHex: String?, emoji: String?) async throws {}
    func deletePinboard(id: UUID) async throws {}
    func deletePinboardForSync(id: UUID, now: Date) async throws {}
    func assign(clipID: UUID, toBoard boardID: UUID) async throws {}
    func unassign(clipID: UUID, fromBoard boardID: UUID) async throws {}
    func removeFromAllBoards(clipID: UUID) async throws {}
    func items(inBoard boardID: UUID) async throws -> [ClipItem] { [] }
    func count(inBoard boardID: UUID) async throws -> Int { 0 }
    func setBoardMembership(clipID: UUID, boardIDs: Set<UUID>) async throws {}

    func items(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func items(ids: [UUID]) async throws -> [ClipItem] { [] }
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func item(id: UUID) async throws -> ClipItem? { nil }
    func count() async throws -> Int { 0 }
    func thumbnailData(for id: UUID) async throws -> Data? { nil }

    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem] { [] }
    func semanticSearch(
        queryVector: [Float], topK: Int, snippetsOnly: Bool
    ) async throws -> [ClipItem] { [] }
    func items(matching rule: SmartCollectionRule, limit: Int) async throws -> [ClipItem] { [] }
}

@Suite("Board suggestion service — pre-embedder guards")
struct BoardSuggestionServiceTests {
    private let userBoard = Pinboard(name: "Dev")

    @Test("Sensitive clips are refused before the store is ever consulted")
    func sensitiveShortCircuits() async {
        let store = FakeStore(boards: [userBoard])
        let item = ClipItem(title: "secret", isSensitive: true)

        let result = await BoardSuggestionService().suggest(for: item, store: store)

        #expect(result == nil)
        // The sensitive guard must fire *before* any store access — otherwise
        // this would be 1. That is the invariant this test protects.
        #expect(await store.pinboardsCalls == 0)
    }

    @Test("No eligible user boards → nil without probing clip membership")
    func noUserBoardsShortCircuits() async {
        // Only a system board (Favorites): filtered out, so there is nothing to
        // suggest and the service returns before touching `boardIDs(forClip:)`.
        let system = Pinboard(id: Pinboard.favoritesID, name: "Favorites", isSystem: true)
        let store = FakeStore(boards: [system])
        let item = ClipItem(title: "hello")

        let result = await BoardSuggestionService().suggest(for: item, store: store)

        #expect(result == nil)
        #expect(await store.pinboardsCalls == 1)  // boards WERE consulted…
        #expect(await store.boardIDsCalls == 0)  // …and the empty set stopped it here.
    }

    @Test("With eligible boards it advances to the semantic path (nil on CI)")
    func reachesSemanticPathButNoAssetsOnCI() async {
        // A real user board and a non-sensitive clip clear every pre-embedder
        // guard, so the flow reaches the content load. On the CI runner the
        // embedder has no on-device assets, so the result is nil — but the call
        // counts prove the service progressed past the board guards rather than
        // bailing early, which is what distinguishes this from the cases above.
        let store = FakeStore(boards: [userBoard])
        let item = ClipItem(title: "hello world")

        let result = await BoardSuggestionService().suggest(for: item, store: store)

        #expect(result == nil)
        #expect(await store.boardIDsCalls == 1)  // fetched the clip's current boards
        #expect(await store.contentCalls == 1)  // and attempted to load content
    }
}
