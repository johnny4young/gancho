import Foundation

/// Minimal persistence facet for capture workflows. Keeping ingestion on this
/// surface prevents coordinators from gaining unrelated list, delete, content,
/// or export responsibilities.
public protocol ClipIngesting: Sendable {
    /// Inserts a clip with its full content. Implementations deduplicate by
    /// `contentHash`: re-copying identical content moves the existing item
    /// to the top instead of duplicating it.
    @discardableResult
    func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem
}

/// One classified text row ready for an approved migration transaction.
/// Import sources in Gancho are text-only today; keeping the canonical text
/// beside its metadata prevents a generic batch API from accidentally gaining
/// authority to write arbitrary foreign blobs.
public struct ClipImportBatchItem: Sendable, Equatable {
    public var item: ClipItem
    public var text: String

    public init(item: ClipItem, text: String) {
        self.item = item
        self.text = text
    }
}

/// Atomic outcome of an approved migration. Only newly inserted rows are
/// returned for post-commit sync; duplicates are left completely unchanged.
public struct ClipImportBatchResult: Sendable, Equatable {
    public var insertedItems: [ClipItem]
    public var skippedDuplicates: Int

    public init(insertedItems: [ClipItem] = [], skippedDuplicates: Int = 0) {
        self.insertedItems = insertedItems
        self.skippedDuplicates = skippedDuplicates
    }
}

/// Narrow persistence surface for migration dry runs and their final atomic
/// commit. Import dedupe intentionally compares content hashes across devices:
/// a migration must not create a local copy of content already synced here.
public protocol ClipImporting: Sendable {
    /// Existing hashes among the proposed set, without loading clip content.
    func existingImportContentHashes(_ hashes: Set<String>) async throws -> Set<String>

    /// Inserts all non-duplicate text rows in one transaction. Cancellation or
    /// an error rolls back the entire batch; existing duplicates are not moved,
    /// retimestamped, pinned, or otherwise mutated.
    func importTextBatch(_ records: [ClipImportBatchItem]) async throws -> ClipImportBatchResult
}

/// Persistence boundary for clip history. The production implementation is
/// GRDB/SQLite (+FTS5); the in-memory implementation backs unit tests and
/// previews. List calls page METADATA only — full content is a separate,
/// per-item fetch so blobs never ride along with scrolling.
public protocol ClipboardStore: ClipIngesting {
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
    nonisolated public var isDurable: Bool { true }
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
public actor InMemoryClipboardStore: ClipboardStore, ClipImporting {
    private var storage: [ClipItem] = []
    private var contents: [UUID: ClipContent] = [:]

    public init() {}

    /// The fallback store loses everything on relaunch — the UI surfaces this.
    nonisolated public var isDurable: Bool { false }

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

    public func existingImportContentHashes(_ hashes: Set<String>) async throws -> Set<String> {
        Set(storage.lazy.map(\.contentHash).filter(hashes.contains))
    }

    public func importTextBatch(
        _ records: [ClipImportBatchItem]
    ) async throws -> ClipImportBatchResult {
        var stagedStorage = storage
        var stagedContents = contents
        var knownHashes = Set(stagedStorage.map(\.contentHash))
        var insertedItems: [ClipItem] = []
        var skippedDuplicates = 0

        for record in records {
            try Task.checkCancellation()
            guard knownHashes.insert(record.item.contentHash).inserted else {
                skippedDuplicates += 1
                continue
            }
            stagedStorage.insert(record.item, at: 0)
            stagedContents[record.item.id] = .text(record.text)
            insertedItems.append(record.item)
        }

        try Task.checkCancellation()
        storage = stagedStorage
        contents = stagedContents
        return ClipImportBatchResult(
            insertedItems: insertedItems,
            skippedDuplicates: skippedDuplicates)
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
