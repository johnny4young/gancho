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

    /// Every column except the payload ones, for queries that build `ClipItem`s.
    ///
    /// `ClipItem` carries no content at all, so a list query that selects
    /// `contentText` decrypts and decodes the full body of every row only to
    /// discard it in `.map(\.item)`. At a page size of 100 that is 100 clip
    /// bodies per scroll, and on an encrypted store every one of them is
    /// decrypted first.
    ///
    /// The non-payload columns stay in the list even when `ClipItem` ignores
    /// them (`isArchived`, `isSnippet`): GRDB decodes `ClipRow` as a whole and
    /// throws `column not found` for a missing NON-optional column — it does
    /// not fall back to the Swift default. Optionals are what may be omitted,
    /// which is exactly what the three payload columns are.
    ///
    /// `ClipRowProjectionTests` fetches through this list, so adding a
    /// non-optional column to `ClipRow` without adding it here fails a test
    /// rather than every list query at runtime.
    static let metadataColumns: [Column] = [
        Column("id"), Column("createdAt"), Column("updatedAt"), Column("lastUsedAt"),
        Column("kind"), Column("title"), Column("preview"), Column("contentHash"),
        Column("sourceAppBundleID"), Column("sourceDeviceName"), Column("isPinned"),
        Column("isSensitive"), Column("expiresAt"), Column("tags"), Column("isArchived"),
        Column("isSnippet"), Column("keyword"), Column("uses")
    ]

    /// The same projection for raw SQL, qualified so it can sit beside a join.
    static let metadataSelectionSQL: String =
        metadataColumns.map { #"clip."\#($0.name)""# }.joined(separator: ", ")

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
