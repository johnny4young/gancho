import ClipboardCore
import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor MergeSyncSpy: SyncEngine {
    private(set) var enqueued: [UUID] = []
    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async { enqueued += items.map(\.id) }
    func enqueueDeletion(ids: [UUID]) async {}
    func enqueue(boards: [Pinboard]) async {}
    func enqueueBoardDeletion(ids: [UUID]) async {}
}

@Suite("Double-copy merge")
struct DoubleCopyMergeTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func copy(
        _ text: String, count: Int, after seconds: TimeInterval = 0,
        app: String? = "com.apple.Safari"
    ) -> CopyObservation {
        CopyObservation(
            text: text, sourceAppBundleID: app,
            change: .init(count: count, observedAt: start.addingTimeInterval(seconds)))
    }

    @Test("Same text, same app, the next change, inside the window")
    func detector() {
        let first = copy("B", count: 5)
        #expect(DoubleCopyDetector.isDoubleCopy(copy("B", count: 6, after: 0.3), after: first))
        #expect(!DoubleCopyDetector.isDoubleCopy(copy("C", count: 6, after: 0.3), after: first))
        #expect(
            !DoubleCopyDetector.isDoubleCopy(
                copy("B", count: 6, after: 0.3, app: "com.apple.mail"), after: first))
        #expect(
            !DoubleCopyDetector.isDoubleCopy(copy("B", count: 7, after: 0.3), after: first),
            "a change between them, even one folded into the same poll, breaks the pair")
        #expect(
            !DoubleCopyDetector.isDoubleCopy(
                copy("B", count: 6, after: DoubleCopyDetector.window + 0.01), after: first))
    }

    @Test("A double copy appends to the clip before it; a third press doesn't")
    func mergerStates() {
        var merger = DoubleCopyMerger()
        let clipA = UUID()
        let clipB = UUID()
        merger.didIngest(copy("A", count: 1), clipID: clipA, isNew: true, canPair: true)
        merger.didIngest(copy("B", count: 2, after: 5), clipID: clipB, isNew: true, canPair: true)
        let second = copy("B", count: 3, after: 5.2)
        #expect(merger.decide(second) == .merge(text: "B", target: clipA, discard: clipB))
        merger.didMerge(into: clipA)
        #expect(merger.decide(copy("B", count: 4, after: 5.4)) == .ingest)

        let clipC = UUID()
        merger.didIngest(copy("C", count: 5, after: 9), clipID: clipC, isNew: false, canPair: true)
        #expect(
            merger.decide(copy("C", count: 6, after: 9.2))
                == .merge(text: "C", target: clipA, discard: nil),
            "a deduped first copy is not discarded")
    }

    @Test("A sensitive first copy or none before it never pairs")
    func mergerRefusesToPair() {
        var merger = DoubleCopyMerger()
        merger.didIngest(copy("A", count: 1), clipID: UUID(), isNew: true, canPair: true)
        merger.didIngest(copy("B", count: 2), clipID: UUID(), isNew: true, canPair: false)
        #expect(merger.decide(copy("B", count: 3, after: 0.1)) == .ingest)

        var fresh = DoubleCopyMerger()
        fresh.didIngest(copy("B", count: 2), clipID: UUID(), isNew: true, canPair: true)
        #expect(fresh.decide(copy("B", count: 3, after: 0.1)) == .ingest, "nothing to append to")
        #expect(fresh.decide(nil) == .ingest)
    }

    private func makeStore() throws -> GRDBClipboardStore {
        try GRDBClipboardStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "merge-\(UUID().uuidString)"))
    }

    @Test("The workflow appends, drops the first copy's clip and chains to three parts")
    func workflowMerges() async throws {
        let store = try makeStore()
        let spy = MergeSyncSpy()
        let target = try await store.insert(ClipItem(contentHash: "a"), content: .text("Ana"))
        let throwaway = try await store.insert(
            ClipItem(contentHash: "b"), content: .text("Cra. 43A"))
        let deletion: @Sendable ([UUID]) async -> Void = { ids in
            for id in ids { try? await store.delete(id: id) }
        }

        let first = await ClipMergeWorkflow().merge(
            "Cra. 43A", into: target.id, discarding: throwaway.id, store: store,
            deletion: deletion, engine: spy)
        guard case .merged(let item, let text, let count) = first else {
            Issue.record("expected a merge, got \(first)")
            return
        }
        #expect(text == "Ana\nCra. 43A")
        #expect(count == 2)
        #expect(item.parts?.split(text) == ["Ana", "Cra. 43A"])
        #expect(try await store.item(id: throwaway.id) == nil)
        #expect(await spy.enqueued == [target.id])

        let second = await ClipMergeWorkflow().merge(
            "+57 300", into: target.id, discarding: nil, store: store, deletion: deletion,
            engine: spy)
        guard case .merged(_, let three, 3) = second else {
            Issue.record("expected three parts, got \(second)")
            return
        }
        #expect(three == "Ana\nCra. 43A\n+57 300")
    }

    @Test("A merge that would form a secret, or into a masked clip, is refused")
    func workflowRefuses() async throws {
        let store = try makeStore()
        let spy = MergeSyncSpy()
        let deletion: @Sendable ([UUID]) async -> Void = { _ in }
        let target = try await store.insert(ClipItem(contentHash: "k"), content: .text("key:"))
        let secret = await ClipMergeWorkflow().merge(
            "AKIAIOSFODNN7EXAMPLE", into: target.id, discarding: nil, store: store,
            deletion: deletion, engine: spy)
        #expect(secret == .refused)
        #expect(try await store.content(for: target.id) == .text("key:"))

        let card = try await store.insert(
            ClipItem(kind: .creditCard, contentHash: "c"), content: .text("4111"))
        let masked = await ClipMergeWorkflow().merge(
            "more", into: card.id, discarding: nil, store: store, deletion: deletion, engine: spy)
        #expect(masked == .refused)
        #expect(await spy.enqueued.isEmpty)
    }

    @Test("A late upload for a deleted clip is dropped; live clips still go")
    func existingClipsOnly() async throws {
        let store = try makeStore()
        let spy = MergeSyncSpy()
        let live = try await store.insert(ClipItem(contentHash: "l"), content: .text("live"))
        let gone = try await store.insert(ClipItem(contentHash: "g"), content: .text("gone"))
        try await store.delete(id: gone.id)

        await ExistingClipsSyncEngine(spy, store: store).enqueue([live, gone])
        #expect(await spy.enqueued == [live.id])
    }
}
