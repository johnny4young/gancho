import Foundation
import GanchoKit

/// Durable-write-then-sync ordering for the Library's snippet drafts, so the
/// view never writes the store directly and every committed edit reaches sync.
public struct SnippetDraftController: Sendable {
    public init() {}

    /// Saves the draft over its snippet. Returns false when the original no
    /// longer exists as a snippet; nothing is enqueued unless the write landed.
    public func save<Store>(
        id: UUID, fields: SnippetDraft.Fields, store: Store, engine: any SyncEngine
    ) async throws -> Bool where Store: SnippetDraftStoring & ClipReading {
        guard
            try await store.updateSnippetDraft(
                id: id, title: fields.title, text: fields.body, keyword: fields.keyword)
        else { return false }
        if let saved = try await store.item(id: id) { await engine.enqueue([saved]) }
        return true
    }

    /// Inserts a recovered or new snippet, then enqueues it.
    public func saveRecovered(
        item: ClipItem, text: String, keyword: String?, isPro: Bool,
        store: any SnippetDraftStoring, engine: any SyncEngine
    ) async throws -> ClipItem {
        let saved = try await store.saveRecoveredSnippet(
            item: item, text: text, keyword: keyword, isPro: isPro)
        await engine.enqueue([saved])
        return saved
    }
}
