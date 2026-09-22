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
        let first = try #require(
            await coordinator.ingestInbox(
                delivery, configuration: configuration, store: store, syncEngine: sync))
        #expect(await sync.enqueued == 1)
        #expect(try inbox.readPending().deliveries.count == 1)
        // The process dies here, before acknowledgement. User deletion must
        // also survive a replay; a content-hash-only dedupe would resurrect it.
        try await store.delete(id: first.item.id)
        let reopened = try GRDBClipboardStore(directory: root.appendingPathComponent("store"))
        let report = try await SharedInboxDrainer().drain(inbox) { retry in
            let duplicate = try await coordinator.ingestInbox(
                retry, configuration: configuration, store: reopened, syncEngine: sync)
            #expect(duplicate == nil)
        }
        #expect(report.acknowledged == 1)
        #expect(await sync.enqueued == 1)
        #expect(try await reopened.items(offset: 0, limit: 10).isEmpty)
        #expect(try inbox.readPending().deliveries.isEmpty)
    }
}
