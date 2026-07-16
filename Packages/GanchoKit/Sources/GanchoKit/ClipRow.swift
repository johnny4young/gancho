import Foundation
import GRDB

/// Database row ↔ domain mapping. Internal: the row schema is a storage
/// detail; everything outside speaks `ClipItem` + `ClipContent`.
struct ClipRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clip"

    /// Shared coders for the `tags` JSON column (default options, so the
    /// stored bytes are unchanged). Hoisted because bulk import/read paths
    /// map thousands of rows — one coder each, not one per row; encode and
    /// decode calls are safe to share across threads.
    static let tagsEncoder = JSONEncoder()
    static let tagsDecoder = JSONDecoder()

    var id: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var kind: String
    var title: String
    var preview: String
    var contentHash: String
    var sourceAppBundleID: String?
    var sourceDeviceName: String?
    var isPinned: Bool
    var isSensitive: Bool
    var expiresAt: Date?
    var tags: String
    var contentText: String?
    var contentBlobHash: String?
    var contentTypeIdentifier: String?
    var isArchived: Bool = false
    var isSnippet: Bool = false
    var keyword: String?
    var uses: Int = 0

    init(item: ClipItem) {
        id = item.id.uuidString
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        lastUsedAt = item.lastUsedAt
        kind = item.kind.rawValue
        title = item.title
        preview = item.preview
        contentHash = item.contentHash
        sourceAppBundleID = item.sourceAppBundleID
        sourceDeviceName = item.sourceDeviceName
        isPinned = item.isPinned
        isSensitive = item.isSensitive
        expiresAt = item.expiresAt
        tags =
            (try? String(data: Self.tagsEncoder.encode(item.tags), encoding: .utf8) ?? "[]")
            ?? "[]"
        contentText = nil
        contentBlobHash = nil
        contentTypeIdentifier = nil
        keyword = item.keyword
        uses = item.uses
    }

    var item: ClipItem {
        ClipItem(
            id: UUID(uuidString: id) ?? UUID(),
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastUsedAt: lastUsedAt,
            kind: ClipContentKind(rawValue: kind) ?? .text,
            title: title,
            preview: preview,
            contentHash: contentHash,
            sourceAppBundleID: sourceAppBundleID,
            sourceDeviceName: sourceDeviceName,
            isPinned: isPinned,
            isSensitive: isSensitive,
            expiresAt: expiresAt,
            tags: (try? Self.tagsDecoder.decode([String].self, from: Data(tags.utf8))) ?? [],
            keyword: keyword,
            uses: uses
        )
    }
}
