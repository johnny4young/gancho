import Foundation

/// The FULL content of a clip, as the store persists it. `ClipItem` carries
/// only metadata + a sanitized preview; the content lives separately so
/// list queries never page blobs into memory.
public enum ClipContent: Sendable, Equatable, Codable {
    /// Plain or rich-degraded text — stored in the database row itself
    /// (text is cheap and full-text search needs it there).
    case text(String)
    /// Binary payloads (images, RTF bytes) — stored on disk through
    /// `BlobStore`, content-addressed; the row keeps the reference.
    case binary(data: Data, typeIdentifier: String)
    /// Copied file references — paths only, never the files' bytes.
    case fileReferences([String])
}
