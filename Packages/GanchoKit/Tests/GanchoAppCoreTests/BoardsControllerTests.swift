import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// Recording fake board store: it answers every `BoardStoring` requirement and
/// counts the ones the controller drives, so a test asserts not just the return
/// value but *which* store calls the control flow made (and did not make) — the
/// gate that keeps these tests non-vacuous. `pinboards()` returns a configurable
/// list so a test can seat the free-tier board count precisely.
private actor FakeBoardStore: BoardStoring {
    let boards: [Pinboard]
    let createdBoard: Pinboard
    let createShouldFail: Bool

    private(set) var pinboardsCalls = 0
    private(set) var createPinboardCalls = 0
    private(set) var assignCalls = 0
    private(set) var unassignCalls = 0
    private(set) var renameCalls = 0
    private(set) var deletePinboardCalls = 0
    private(set) var deletePinboardForSyncCalls = 0

    init(
        boards: [Pinboard], createdBoard: Pinboard = Pinboard(name: "New"),
        createShouldFail: Bool = false
    ) {
        self.boards = boards
        self.createdBoard = createdBoard
        self.createShouldFail = createShouldFail
    }

    func pinboards() async throws -> [Pinboard] {
        pinboardsCalls += 1
        return boards
    }
    func createPinboard(name: String, sfSymbol: String) async throws -> Pinboard {
        createPinboardCalls += 1
        if createShouldFail { throw FakeBoardError.create }
        return createdBoard
    }
    func renameBoard(id: UUID, name: String) async throws { renameCalls += 1 }
    func deletePinboard(id: UUID) async throws { deletePinboardCalls += 1 }
    func deletePinboardForSync(id: UUID, now: Date) async throws { deletePinboardForSyncCalls += 1 }
    func assign(clipID: UUID, toBoard boardID: UUID) async throws { assignCalls += 1 }
    func unassign(clipID: UUID, fromBoard boardID: UUID) async throws { unassignCalls += 1 }
    func removeFromAllBoards(clipID: UUID) async throws {}
    func boardIDs(forClip clipID: UUID) async throws -> Set<UUID> { [] }
    func items(inBoard boardID: UUID) async throws -> [ClipItem] { [] }
    func count(inBoard boardID: UUID) async throws -> Int { 0 }
    func setBoardMembership(clipID: UUID, boardIDs: Set<UUID>) async throws {}
}

private enum FakeBoardError: Error { case create }

/// Records the board-metadata enqueues the controller fires, so a test proves
/// the sync side effects (upsert on create/rename, deletion on sync-on delete)
/// happen exactly once and carry the right ids.
private actor FakeBoardEngine: SyncEngine {
    private(set) var enqueueItemsCalls = 0
    private(set) var enqueueBoardsCalls = 0
    private(set) var enqueueBoardDeletionCalls = 0
    private(set) var lastEnqueuedItemIDs: [UUID] = []
    private(set) var lastEnqueuedBoardIDs: [UUID] = []
    private(set) var lastDeletedBoardIDs: [UUID] = []

    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async {
        enqueueItemsCalls += 1
        lastEnqueuedItemIDs = items.map(\.id)
    }
    func enqueueDeletion(ids: [UUID]) async {}
    func enqueue(boards: [Pinboard]) async {
        enqueueBoardsCalls += 1
        lastEnqueuedBoardIDs = boards.map(\.id)
    }
    func enqueueBoardDeletion(ids: [UUID]) async {
        enqueueBoardDeletionCalls += 1
        lastDeletedBoardIDs = ids
    }
}

@Suite("Boards controller — mutation control flow")
@MainActor
struct BoardsControllerTests {
    /// `PinLimits.freeMaxPinboards` user boards is the wall — a free user at it
    /// must be gated before any create write happens.
    @Test("At the free limit: onFreeLimit fires, createPinboard is never called")
    func freeLimitBlocksCreate() async {
        let full = (0..<PinLimits.freeMaxPinboards).map { Pinboard(name: "B\($0)") }
        let store = FakeBoardStore(boards: full)
        let engine = FakeBoardEngine()
        var freeLimitFired = false

        let outcome = await BoardsController().createBoard(
            name: "New", filing: nil, store: store, engine: engine, isPro: false,
            onFreeLimit: { freeLimitFired = true }, onAssigned: {})

        #expect(outcome == .blocked)
        #expect(freeLimitFired)
        #expect(await store.createPinboardCalls == 0)
        #expect(await engine.enqueueBoardsCalls == 0)
    }

    @Test("Under the limit: creates, enqueues once, does not gate")
    func underLimitCreatesAndEnqueuesOnce() async {
        let created = Pinboard(name: "New")
        let store = FakeBoardStore(boards: [], createdBoard: created)
        let engine = FakeBoardEngine()
        var freeLimitFired = false

        let outcome = await BoardsController().createBoard(
            name: "New", filing: nil, store: store, engine: engine, isPro: false,
            onFreeLimit: { freeLimitFired = true }, onAssigned: {})

        #expect(outcome == .created(created.id))
        #expect(!freeLimitFired)
        #expect(await store.createPinboardCalls == 1)
        #expect(await engine.enqueueBoardsCalls == 1)
        // No item filed, so membership is untouched.
        #expect(await store.assignCalls == 0)
    }

    @Test("Filing an item also assigns once and fires onAssigned, in order")
    func filingAssignsAndFiresOnAssigned() async {
        let created = Pinboard(name: "New")
        let store = FakeBoardStore(boards: [], createdBoard: created)
        let engine = FakeBoardEngine()
        var assignedFired = false
        let item = ClipItem(title: "hello")

        let outcome = await BoardsController().createBoard(
            name: "New", filing: item, store: store, engine: engine, isPro: false,
            onFreeLimit: {}, onAssigned: { assignedFired = true })

        #expect(outcome == .created(created.id))
        #expect(await engine.enqueueBoardsCalls == 1)
        #expect(await engine.enqueueItemsCalls == 1)
        #expect(await engine.lastEnqueuedItemIDs == [item.id])
        #expect(await store.assignCalls == 1)
        #expect(assignedFired)
    }

    @Test("System boards do not count against the free limit")
    func systemBoardExcludedFromLimit() async {
        // One below the wall in USER boards, plus a system board that must be
        // filtered out — so the create is allowed. Were the filter dropped, the
        // count would hit the wall and this would block.
        let system = Pinboard(id: Pinboard.favoritesID, name: "Favorites", isSystem: true)
        let user = (0..<(PinLimits.freeMaxPinboards - 1)).map { Pinboard(name: "B\($0)") }
        let store = FakeBoardStore(boards: [system] + user)
        let engine = FakeBoardEngine()
        var freeLimitFired = false

        let outcome = await BoardsController().createBoard(
            name: "New", filing: nil, store: store, engine: engine, isPro: false,
            onFreeLimit: { freeLimitFired = true }, onAssigned: {})

        #expect(!freeLimitFired)
        #expect(await store.createPinboardCalls == 1)
        if case .created = outcome {} else { Issue.record("expected .created, got \(outcome)") }
    }

    @Test("Pro tier bypasses the board limit")
    func proBypassesLimit() async {
        let full = (0..<(PinLimits.freeMaxPinboards + 5)).map { Pinboard(name: "B\($0)") }
        let store = FakeBoardStore(boards: full)
        let engine = FakeBoardEngine()

        let outcome = await BoardsController().createBoard(
            name: "New", filing: nil, store: store, engine: engine, isPro: true,
            onFreeLimit: {}, onAssigned: {})

        #expect(await store.createPinboardCalls == 1)
        if case .created = outcome {} else { Issue.record("expected .created, got \(outcome)") }
    }

    @Test("A failed create returns .failed and enqueues nothing")
    func createFailureReturnsFailed() async {
        let store = FakeBoardStore(boards: [], createShouldFail: true)
        let engine = FakeBoardEngine()

        let outcome = await BoardsController().createBoard(
            name: "New", filing: ClipItem(title: "x"), store: store, engine: engine,
            isPro: false, onFreeLimit: {}, onAssigned: {})

        #expect(outcome == .failed)
        #expect(await store.createPinboardCalls == 1)
        #expect(await engine.enqueueBoardsCalls == 0)
        #expect(await store.assignCalls == 0)
    }

    @Test("Delete with sync on tombstones and enqueues the deletion")
    func deleteWithSyncTombstones() async {
        let board = Pinboard(name: "Docs")
        let store = FakeBoardStore(boards: [board])
        let engine = FakeBoardEngine()

        await BoardsController().deleteBoard(
            board, store: store, engine: engine, syncEnabled: true)

        #expect(await store.deletePinboardForSyncCalls == 1)
        #expect(await engine.enqueueBoardDeletionCalls == 1)
        #expect(await engine.lastDeletedBoardIDs == [board.id])
        // The sync branch must NOT also take the plain-delete path.
        #expect(await store.deletePinboardCalls == 0)
    }

    @Test("Delete with sync off plain-deletes and enqueues nothing")
    func deleteWithoutSyncPlainDeletes() async {
        let board = Pinboard(name: "Docs")
        let store = FakeBoardStore(boards: [board])
        let engine = FakeBoardEngine()

        await BoardsController().deleteBoard(
            board, store: store, engine: engine, syncEnabled: false)

        #expect(await store.deletePinboardCalls == 1)
        #expect(await store.deletePinboardForSyncCalls == 0)
        #expect(await engine.enqueueBoardDeletionCalls == 0)
    }

    @Test("Membership assign routes to assign, not unassign")
    func membershipAssignRoutes() async {
        let store = FakeBoardStore(boards: [])
        let engine = FakeBoardEngine()
        let item = ClipItem(title: "x")

        await BoardsController().setBoardMembership(
            item, board: Pinboard(name: "Docs"), member: true, store: store, engine: engine)

        #expect(await store.assignCalls == 1)
        #expect(await store.unassignCalls == 0)
        #expect(await engine.enqueueItemsCalls == 1)
        #expect(await engine.lastEnqueuedItemIDs == [item.id])
    }

    @Test("Membership unassign routes to unassign, not assign")
    func membershipUnassignRoutes() async {
        let store = FakeBoardStore(boards: [])
        let engine = FakeBoardEngine()
        let item = ClipItem(title: "x")

        await BoardsController().setBoardMembership(
            item, board: Pinboard(name: "Docs"), member: false, store: store, engine: engine)

        #expect(await store.unassignCalls == 1)
        #expect(await store.assignCalls == 0)
        #expect(await engine.enqueueItemsCalls == 1)
        #expect(await engine.lastEnqueuedItemIDs == [item.id])
    }

    @Test("Rename writes the name and enqueues the updated board once")
    func renameEnqueuesUpdatedBoard() async {
        let board = Pinboard(name: "Docs")
        let store = FakeBoardStore(boards: [board])
        let engine = FakeBoardEngine()

        await BoardsController().renameBoard(
            board, name: "Papers", store: store, engine: engine)

        #expect(await store.renameCalls == 1)
        #expect(await engine.enqueueBoardsCalls == 1)
        #expect(await engine.lastEnqueuedBoardIDs == [board.id])
    }
}
