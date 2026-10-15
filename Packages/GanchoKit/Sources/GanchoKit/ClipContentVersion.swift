import Foundation

/// The persisted revision and masking identity of a preview request. Local
/// text edits preserve the deduplication hash, so the timestamp is required.
/// Usage bookkeeping does not advance this revision.
/// This value stays in memory; it is never logged or sent as telemetry.
public struct ClipContentVersion: Hashable, Sendable {
    public let id: UUID
    public let contentHash: String
    public let updatedAt: Date
    public let expiresAt: Date?
    public let kind: ClipContentKind
    public let isSensitive: Bool

    public init(_ item: ClipItem) {
        id = item.id
        contentHash = item.contentHash
        updatedAt = item.updatedAt
        expiresAt = item.expiresAt
        kind = item.kind
        isSensitive = item.isSensitive
    }
}
