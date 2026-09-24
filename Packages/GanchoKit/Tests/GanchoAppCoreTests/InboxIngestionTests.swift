import Foundation
import GanchoKit
import Testing

@testable import ClipboardCore
@testable import GanchoAppCore

private actor InboxSyncSpy: SyncEngine {
    private(set) var enqueued = 0
    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async { enqueued += items.count }
    func enqueueDeletion(ids: [UUID]) async {}
    func enqueue(boards: [Pinboard]) async {}
    func enqueueBoardDeletion(ids: [UUID]) async {}
}

@Suite("Inbox ingestion — durable restart and effect replay")
struct InboxIngestionTests {
    @Test("Crash between commit and ack replays receipt without sync or resurrection")
    func crashBeforeAcknowledgement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "inbox-end-to-end-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedInbox(
            directory: root.appendingPathComponent("inbox"), key: Data(repeating: 0xC3, count: 32))
        try inbox.deposit(
            .init(capture: PasteboardCapture(text: "synthetic shared item"), kind: .text))
        let delivery = try #require(inbox.readPending().deliveries.first)
        let store = try GRDBClipboardStore(directory: root.appendingPathComponent("store"))
        let sync = InboxSyncSpy()
        let coordinator = ClipIngestionCoordinator()
        let configuration = ClipIngestionCoordinator.Configuration(
            tier: .free, intelligence: .init())
        let firstResult = try await coordinator.ingestInbox(
            delivery, configuration: configuration, store: store, syncEngine: sync)
        guard case .inserted(let first) = firstResult else {
            Issue.record("first delivery must insert")
            return
        }
        #expect(await sync.enqueued == 1)
        #expect(try inbox.readPending().deliveries.count == 1)
        // The process dies here, before acknowledgement. User deletion must
        // also survive a replay; a content-hash-only dedupe would resurrect it.
        try await store.delete(id: first.item.id)
        let reopened = try GRDBClipboardStore(directory: root.appendingPathComponent("store"))
        let report = try await SharedInboxDrainer().drain(inbox) { retry in
            let duplicate = try await coordinator.ingestInbox(
                retry, configuration: configuration, store: reopened, syncEngine: sync)
            guard case .replayed(nil) = duplicate else {
                Issue.record("deleted clip must not be recreated")
                return
            }
        }
        #expect(report.acknowledged == 1)
        #expect(await sync.enqueued == 1)
        #expect(try await reopened.items(offset: 0, limit: 10).isEmpty)
        #expect(try inbox.readPending().deliveries.isEmpty)
    }

    @Test("Crash immediately after receipt commit retries effects without reinsertion")
    func crashImmediatelyAfterCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "inbox-early-crash-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = SharedInbox(
            directory: root.appendingPathComponent("inbox"), key: Data(repeating: 0xC3, count: 32))
        try inbox.deposit(.init(capture: PasteboardCapture(text: "synthetic replay"), kind: .text))
        let delivery = try #require(inbox.readPending().deliveries.first)
        let store = try GRDBClipboardStore(directory: root.appendingPathComponent("store"))
        let item = ClipItem(contentHash: "synthetic-replay")
        guard
            case .inserted(let stored) = try await store.insertInboxDelivery(
                id: delivery.id, item: item, content: .text("synthetic replay"))
        else {
            Issue.record("initial transaction must insert")
            return
        }
        let before = try await store.item(id: stored.id)
        let sync = InboxSyncSpy()
        let report = try await SharedInboxDrainer().drain(inbox) { retry in
            let result = try await ClipIngestionCoordinator().ingestInbox(
                retry, configuration: .init(tier: .pro, intelligence: .init()),
                store: store, syncEngine: sync)
            guard case .replayed(let outcome?) = result else {
                Issue.record("committed row must be available for effect retry")
                return
            }
            #expect(outcome.item.id == stored.id)
            #expect(!outcome.isNew)
            #expect(!outcome.enrichment.isEmpty)
        }
        #expect(report.acknowledged == 1)
        #expect(await sync.enqueued == 1)
        #expect(try await store.item(id: stored.id) == before)
        #expect(try await store.items(offset: 0, limit: 10).count == 1)
    }
}
