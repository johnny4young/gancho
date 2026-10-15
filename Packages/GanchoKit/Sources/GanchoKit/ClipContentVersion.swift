import Foundation

/// The content and masking identity of a preview request. Usage, title, and
/// board changes do not invalidate an image decode or a full-text preview.
/// This value stays in memory; it is never logged or sent as telemetry.
public struct ClipContentVersion: Hashable, Sendable {
    public let id: UUID
    public let contentHash: String
    public let kind: ClipContentKind
    public let isSensitive: Bool

    public init(_ item: ClipItem) {
        id = item.id
        contentHash = item.contentHash
        kind = item.kind
        isSensitive = item.isSensitive
    }
}
