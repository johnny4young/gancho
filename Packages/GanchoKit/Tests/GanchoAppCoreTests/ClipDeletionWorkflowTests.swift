import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private enum FakeDeletionError: Error { case failure }

/// Recording store that can fail a chosen subset of ids, so a test asserts both
/// the outcome and exactly which store calls the workflow made — the gate that
/// keeps "only committed ids are enqueued" from passing vacuously.
private actor DeletionStoreSpy: ClipboardStore, ClipMutating {
    private let failing: Set<UUID>
    private(set) var plainDeletes: [UUID] = []
    private(set) var syncDeletes: [UUID] = []

    init(failing: Set<UUID> = []) { self.failing = failing }

    func delete(id: UUID) async throws {
        plainDeletes.append(id)
        if failing.contains(id) { throw FakeDeletionError.failure }
    }

    func deleteForSync(id: UUID, now _: Date) async throws {
        syncDeletes.append(id)
        if failing.contains(id) { throw FakeDeletionError.failure }
    }

    // Unused requirements.
    @discardableResult
    func insert(_ item: ClipItem, content _: ClipContent?) async throws -> ClipItem { item }
    func items(offset _: Int, limit _: Int) async throws -> [ClipItem] { [] }
    func count() async throws -> Int { 0 }
    func content(for _: UUID) async throws -> ClipContent? { nil }
    func exportJSON() async throws -> Data { Data() }
    func exportCSV() async throws -> Data { Data() }
    @discardableResult
    func deleteAllSensitive() async throws -> Int { 0 }
    func setPinned(id _: UUID, _: Bool) async throws {}
    func recordUse(id _: UUID, now _: Date) async throws {}
}

private actor DeletionEngineSpy: SyncEngine {
    private(set) var enqueuedDeletions: [[UUID]] = []

    func start() async throws {}
    func stop() async {}
    func enqueue(_: [ClipItem]) async {}
    func enqueueDeletion(ids: [UUID]) async { enqueuedDeletions.append(ids) }
    func enqueue(boards _: [Pinboard]) async {}
    func enqueueBoardDeletion(ids _: [UUID]) async {}
}

@Suite("Clip deletion workflow — tombstone before propagation")
struct ClipDeletionWorkflowTests {
    private let workflow = ClipDeletionWorkflow()

    @Test("A failed tombstone never propagates the deletion to other devices")
    func failedTombstoneIsNotEnqueued() async {
        let id = UUID()
        let store = DeletionStoreSpy(failing: [id])
        let engine = DeletionEngineSpy()

        let outcome = await workflow.delete(
            ids: [id], store: store, syncStore: store, engine: engine, syncEnabled: true)

        #expect(outcome == .failed)
        #expect(await store.syncDeletes == [id])
        #expect(await engine.enqueuedDeletions.isEmpty)
        // The plain path must not be a silent second attempt: a failed
        // tombstone leaves the row for the next try, it does not drop it.
        #expect(await store.plainDeletes.isEmpty)
    }

    @Test("A partly failed batch enqueues only the ids whose tombstone committed")
    func partialBatchEnqueuesOnlyCommitted() async {
        let first = UUID()
        let broken = UUID()
        let last = UUID()
        let store = DeletionStoreSpy(failing: [broken])
        let engine = DeletionEngineSpy()

        let outcome = await workflow.delete(
            ids: [first, broken, last], store: store, syncStore: store, engine: engine,
            syncEnabled: true)

        #expect(outcome == .partial(failed: [broken]))
        #expect(await engine.enqueuedDeletions == [[first, last]])
    }

    @Test("Every tombstone committing reports a propagated deletion")
    func fullBatchPropagates() async {
        let ids = [UUID(), UUID()]
        let store = DeletionStoreSpy()
        let engine = DeletionEngineSpy()

        let outcome = await workflow.delete(
            ids: ids, store: store, syncStore: store, engine: engine, syncEnabled: true)

        #expect(outcome == .deleted(propagated: true))
        #expect(await store.syncDeletes == ids)
        #expect(await engine.enqueuedDeletions == [ids])
    }

    @Test("Sync off deletes locally and enqueues nothing")
    func syncOffUsesPlainDelete() async {
        let ids = [UUID(), UUID()]
        let store = DeletionStoreSpy()
        let engine = DeletionEngineSpy()

        let outcome = await workflow.delete(
            ids: ids, store: store, syncStore: store, engine: engine, syncEnabled: false)

        #expect(outcome == .deleted(propagated: false))
        #expect(await store.plainDeletes == ids)
        #expect(await store.syncDeletes.isEmpty)
        #expect(await engine.enqueuedDeletions.isEmpty)
    }

    @Test("Sync on without a durable facet still deletes locally, as the shells did")
    func syncOnWithoutSyncStoreFallsBackToPlainDelete() async {
        let ids = [UUID()]
        let store = DeletionStoreSpy()
        let engine = DeletionEngineSpy()

        let outcome = await workflow.delete(
            ids: ids, store: store, syncStore: nil, engine: engine, syncEnabled: true)

        #expect(outcome == .deleted(propagated: false))
        #expect(await store.plainDeletes == ids)
        #expect(await engine.enqueuedDeletions.isEmpty)
    }

    @Test("A failed local delete with sync off reports failure and touches no engine")
    func failedPlainDeleteReportsFailure() async {
        let id = UUID()
        let store = DeletionStoreSpy(failing: [id])
        let engine = DeletionEngineSpy()

        let outcome = await workflow.delete(
            ids: [id], store: store, syncStore: store, engine: engine, syncEnabled: false)

        #expect(outcome == .failed)
        #expect(await engine.enqueuedDeletions.isEmpty)
    }

    @Test("An empty request is a no-op rather than an empty enqueue")
    func emptyRequestDoesNothing() async {
        let store = DeletionStoreSpy()
        let engine = DeletionEngineSpy()

        let outcome = await workflow.delete(
            ids: [], store: store, syncStore: store, engine: engine, syncEnabled: true)

        #expect(outcome == .deleted(propagated: false))
        #expect(await store.syncDeletes.isEmpty)
        #expect(await engine.enqueuedDeletions.isEmpty)
    }
}
