import Foundation

/// Persistence boundary for clip history. The production implementation is
/// GRDB/SQLite + FTS5 (backlog E3.1/E3.2, validated by spike S0.2); the
/// in-memory implementation below backs unit tests and previews.
public protocol ClipboardStore: Sendable {
    /// Inserts a clip, deduplicating by `contentHash`: re-copying identical
    /// content moves the existing item to the top instead of duplicating it.
    @discardableResult
    func insert(_ item: ClipItem) async -> ClipItem
    func items() async -> [ClipItem]
    func delete(id: UUID) async
}

/// Test/preview store. Newest first; dedupe-by-hash matches E1.3 semantics.
public actor InMemoryClipboardStore: ClipboardStore {
    private var storage: [ClipItem] = []

    public init() {}

    @discardableResult
    public func insert(_ item: ClipItem) async -> ClipItem {
        if let index = storage.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var existing = storage.remove(at: index)
            existing.lastUsedAt = .now
            existing.updatedAt = .now
            storage.insert(existing, at: 0)
            return existing
        }
        storage.insert(item, at: 0)
        return item
    }

    public func items() async -> [ClipItem] {
        storage
    }

    public func delete(id: UUID) async {
        storage.removeAll { $0.id == id }
    }
}
