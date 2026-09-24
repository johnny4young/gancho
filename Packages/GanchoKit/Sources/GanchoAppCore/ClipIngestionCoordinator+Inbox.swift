import ClipboardCore
import GanchoKit

extension ClipIngestionCoordinator {
    public enum InboxResult: Sendable {
        case inserted(Outcome)
        /// The row may be gone after a user deletion; never recreate it.
        case replayed(Outcome?)
    }

    /// A receipt replay never reinserts or bumps recency. It does retry sync
    /// scheduling and eligible enrichment before the caller acknowledges the
    /// file, closing the crash window immediately after the SQLite commit.
    public func ingestInbox(
        _ delivery: SharedInbox.Delivery,
        configuration: Configuration,
        store: any InboxClipIngesting,
        syncEngine: any SyncEngine
    ) async throws -> InboxResult {
        do {
            let outcome = try await ingest(
                delivery.prepared.capture, configuration: configuration,
                store: ReceiptStore(store: store, deliveryID: delivery.id), syncEngine: syncEngine)
            return .inserted(outcome)
        } catch ReceiptStore.Replay.alreadyCommitted {
            guard let item = try await store.itemForInboxDelivery(id: delivery.id) else {
                return .replayed(nil)
            }
            await syncEngine.enqueue([item])
            return .replayed(
                replayOutcome(
                    for: item, capture: delivery.prepared.capture, configuration: configuration))
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
