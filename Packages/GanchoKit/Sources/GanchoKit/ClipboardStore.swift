import Foundation

/// Persistence boundary for clip history. The production implementation is
/// GRDB/SQLite (+FTS5); the in-memory implementation backs unit tests and
/// previews. List calls page METADATA only — full content is a separate,
/// per-item fetch so blobs never ride along with scrolling.
public protocol ClipboardStore: Sendable {
    /// Inserts a clip with its full content. Implementations deduplicate by
    /// `contentHash`: re-copying identical content moves the existing item
    /// to the top instead of duplicating it.
    @discardableResult
    func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem

    /// Newest first (pins float to the top), paged.
    func items(offset: Int, limit: Int) async throws -> [ClipItem]

    func count() async throws -> Int

    func delete(id: UUID) async throws

    /// Full content for paste-back/detail — the only blob-loading call.
    func content(for id: UUID) async throws -> ClipContent?

    /// Exports are always available, on every tier — no data hostage.
    func exportJSON() async throws -> Data
    func exportCSV() async throws -> Data

    /// Whether writes survive an app relaunch. `false` only for the in-memory
    /// fallback used when the durable store can't open — so the UI can warn the
    /// user their history isn't actually being saved instead of failing silent.
    nonisolated var isDurable: Bool { get }
}

extension ClipboardStore {
    /// Durable by default; the in-memory fallback overrides to `false`.
    public nonisolated var isDurable: Bool { true }
}

extension ClipboardStore {
    /// Metadata-only insert (intent surfaces that have no content body).
    @discardableResult
    public func insert(_ item: ClipItem) async throws -> ClipItem {
        try await insert(item, content: nil)
    }

    /// First page, default size — shells and previews.
    public func items() async throws -> [ClipItem] {
        try await items(offset: 0, limit: 200)
    }
}

/// Test/preview store. Newest first; dedupe-by-hash matches the capture
/// semantics (re-copying identical content moves it to the top).
public actor InMemoryClipboardStore: ClipboardStore {
    private var storage: [ClipItem] = []
    private var contents: [UUID: ClipContent] = [:]

    public init() {}

    /// The fallback store loses everything on relaunch — the UI surfaces this.
    public nonisolated var isDurable: Bool { false }

    @discardableResult
    public func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem {
        if let index = storage.firstIndex(where: {
            $0.contentHash == item.contentHash
                && $0.sourceDeviceName == item.sourceDeviceName
        }) {
            var existing = storage.remove(at: index)
            existing.lastUsedAt = .now
            existing.updatedAt = .now
            storage.insert(existing, at: 0)
            return existing
        }
        storage.insert(item, at: 0)
        if let content {
            contents[item.id] = content
        }
        return item
    }

    public func items(offset: Int, limit: Int) async throws -> [ClipItem] {
        Array(storage.dropFirst(offset).prefix(limit))
    }

    public func count() async throws -> Int {
        storage.count
    }

    public func delete(id: UUID) async throws {
        storage.removeAll { $0.id == id }
        contents[id] = nil
    }

    public func content(for id: UUID) async throws -> ClipContent? {
        contents[id]
    }

    public func exportJSON() async throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(storage)
    }

    public func exportCSV() async throws -> Data {
        var csv = "id,createdAt,kind,preview\n"
        let formatter = ISO8601DateFormatter()
        for item in storage {
            csv += "\(item.id),\(formatter.string(from: item.createdAt)),"
            csv +=
                "\(item.kind.rawValue),\"\(item.preview.replacingOccurrences(of: "\"", with: "\"\""))\"\n"
        }
        return Data(csv.utf8)
    }
}
