import CryptoKit
import Foundation

/// A single captured clipboard item. Value type by design: the store owns
/// persistence; sync goes through the `SyncEngine` boundary.
///
/// CloudKit-compatibility rules (decided 2026-06): defaults or optionals
/// everywhere, no unique constraints, deletes travel as tombstones.
public struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?

    public var kind: ClipContentKind
    /// Short title for lists. Empty until the user or auto-titling names it.
    public var title: String
    /// Sanitized preview for fast UI. Full content may be encrypted at rest.
    public var preview: String
    /// SHA-256 of content + kind; local dedupe key (re-copy moves to top).
    public var contentHash: String

    public var sourceAppBundleID: String?
    public var sourceDeviceName: String?

    public var isPinned: Bool
    public var isSensitive: Bool
    public var expiresAt: Date?
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastUsedAt: Date? = nil,
        kind: ClipContentKind = .text,
        title: String = "",
        preview: String = "",
        contentHash: String = "",
        sourceAppBundleID: String? = nil,
        sourceDeviceName: String? = nil,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        expiresAt: Date? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.kind = kind
        self.title = title
        self.preview = preview
        self.contentHash = contentHash
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceDeviceName = sourceDeviceName
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.expiresAt = expiresAt
        self.tags = tags
    }

    /// Dedupe key for a piece of content. Stable across devices so sync
    /// can also use it to avoid ping-pong duplicates.
    public static func hash(of content: Data, kind: ClipContentKind) -> String {
        var hasher = SHA256()
        hasher.update(data: content)
        hasher.update(data: Data(kind.rawValue.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func hash(of text: String, kind: ClipContentKind) -> String {
        hash(of: Data(text.utf8), kind: kind)
    }
}
