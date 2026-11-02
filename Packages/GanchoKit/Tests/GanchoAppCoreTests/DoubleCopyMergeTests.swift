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

private actor SplitRecorder {
    private(set) var texts: [String] = []

    /// Returns how many parts were saved so far, this one included.
    func record(_ text: String) -> Int {
        texts.append(text)
        return texts.count
    }
}

private enum MergeTestFailure: Error {
    case notMerged
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

    @Test("A copy that dedupes into the clip before it never pairs with that clip")
    func mergerNeverTargetsItself() {
        var merger = DoubleCopyMerger()
        let clip = UUID()
        merger.didIngest(copy("C", count: 1), clipID: clip, isNew: true, canPair: true)
        #expect(merger.decide(copy("C", count: 2, after: 0.1)) == .ingest)
        merger.didIngest(copy("C", count: 2, after: 0.1), clipID: clip, isNew: false, canPair: true)
        #expect(merger.decide(copy("C", count: 3, after: 0.2)) == .ingest, "a third press")
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

    private func mergedClip(
        _ store: GRDBClipboardStore, _ first: String, _ second: String, spy: MergeSyncSpy
    ) async throws -> ClipItem {
        let target = try await store.insert(
            ClipItem(contentHash: UUID().uuidString), content: .text(first))
        let outcome = await ClipMergeWorkflow().merge(
            second, into: target.id, discarding: nil, store: store, deletion: { _ in },
            engine: spy)
        guard case .merged(let item, _, _) = outcome else {
            throw MergeTestFailure.notMerged
        }
        return item
    }

    @Test("A separator change rewrites in place; the same separator or an edit refuses")
    func workflowRejoins() async throws {
        let store = try makeStore()
        let spy = MergeSyncSpy()
        let merged = try await mergedClip(store, "Ana", "Cra. 43A", spy: spy)

        let outcome = await ClipMergeWorkflow().rejoin(
            merged.id, with: .comma, store: store, engine: spy)
        guard case .merged(let item, let text, 2) = outcome else {
            Issue.record("expected a rejoin, got \(outcome)")
            return
        }
        #expect(text == "Ana, Cra. 43A")
        #expect(item.parts?.separator == .comma)
        #expect(item.lastUsedAt == merged.lastUsedAt, "a separator change keeps its place")
        #expect(try await store.content(for: merged.id) == .text(text))
        #expect(await spy.enqueued == [merged.id, merged.id])

        #expect(
            await ClipMergeWorkflow().rejoin(merged.id, with: .comma, store: store, engine: spy)
                == .refused)
        try await store.updateClipText(id: merged.id, text: "edited")
        #expect(
            await ClipMergeWorkflow().rejoin(merged.id, with: .space, store: store, engine: spy)
                == .refused)
    }

    @Test("Split saves each part in order, then drops the merged clip")
    func workflowSplits() async throws {
        let store = try makeStore()
        let merged = try await mergedClip(store, "Ana", "Cra. 43A", spy: MergeSyncSpy())
        let remove: @Sendable (UUID) async -> Bool = { id in
            (try? await store.delete(id: id)) != nil
        }
        let saved = SplitRecorder()
        let ids = [UUID(), UUID()]

        let outcome = await ClipMergeWorkflow().split(
            merged.id, store: store,
            save: { text in ids[await saved.record(text) - 1] }, remove: remove)
        #expect(outcome == .split(ids))
        #expect(await saved.texts == ["Ana", "Cra. 43A"])
        #expect(try await store.item(id: merged.id) == nil)
    }

    @Test("Split keeps the merged clip when a part fails, and refuses a plain clip")
    func workflowSplitRefusals() async throws {
        let store = try makeStore()
        let merged = try await mergedClip(store, "Ana", "Cra. 43A", spy: MergeSyncSpy())
        let remove: @Sendable (UUID) async -> Bool = { id in
            (try? await store.delete(id: id)) != nil
        }
        let first = UUID()
        let calls = SplitRecorder()
        let failed = await ClipMergeWorkflow().split(
            merged.id, store: store,
            save: { text in await calls.record(text) == 1 ? first : nil }, remove: remove)
        #expect(failed == .failed(saved: [first]))
        #expect(try await store.item(id: merged.id) != nil)

        let selfSave = await ClipMergeWorkflow().split(
            merged.id, store: store, save: { _ in merged.id }, remove: remove)
        #expect(selfSave == .failed(saved: []), "a part that lands in the merged clip keeps it")

        let undeletable = await ClipMergeWorkflow().split(
            merged.id, store: store, save: { _ in UUID() }, remove: { _ in false })
        guard case .failed(let parts) = undeletable else {
            Issue.record("a failed delete must not report a split, got \(undeletable)")
            return
        }
        #expect(parts.count == 2)

        let plain = try await store.insert(ClipItem(contentHash: "plain"), content: .text("one"))
        #expect(
            await ClipMergeWorkflow().split(
                plain.id, store: store, save: { _ in UUID() }, remove: remove) == .refused)
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
