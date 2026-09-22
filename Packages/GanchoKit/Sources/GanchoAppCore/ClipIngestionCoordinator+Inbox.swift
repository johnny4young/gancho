import ClipboardCore
import GanchoKit

extension ClipIngestionCoordinator {
    /// Nil means an existing durable receipt, even when the user since deleted
    /// the clip. No sync, recency or enrichment effects repeat on that path.
    public func ingestInbox(
        _ delivery: SharedInbox.Delivery,
        configuration: Configuration,
        store: any InboxClipIngesting,
        syncEngine: any SyncEngine
    ) async throws -> Outcome? {
        do {
            return try await ingest(
                delivery.prepared.capture, configuration: configuration,
                store: ReceiptStore(store: store, deliveryID: delivery.id), syncEngine: syncEngine)
        } catch ReceiptStore.Replay.alreadyCommitted {
            return nil
        }
    }
}

private struct ReceiptStore: ClipIngesting {
    enum Replay: Error { case alreadyCommitted }
    let store: any InboxClipIngesting
    let deliveryID: String

    func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem {
        switch try await store.insertInboxDelivery(id: deliveryID, item: item, content: content) {
        case .inserted(let stored): return stored
        case .alreadyCommitted: throw Replay.alreadyCommitted
        }
    }
}
