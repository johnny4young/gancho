import Foundation
import GanchoKit

/// Content handed to an explicit large-preview surface. Keeping loading policy
/// in the shared core makes every caller fail closed for sensitive kinds while
/// preserving the original payload only in memory.
public enum ClipPreviewPayload: Sendable, Equatable {
    case masked(String)
    case text(String)
    case binary(data: Data, typeIdentifier: String)
    case fileReferences([String])
    case unavailable
}

/// Lazily resolves one clip's full content only after the user asks for a
/// preview. Sensitive or intrinsically masked kinds return their sanitized
/// metadata preview without touching the content store.
public struct ClipPreviewLoader: Sendable {
    public init() {}

    public func load(
        _ item: ClipItem,
        loadContent: @Sendable (UUID) async throws -> ClipContent?
    ) async -> ClipPreviewPayload {
        guard !item.isSensitive, !item.kind.prefersMaskedPreview else {
            return .masked(item.preview)
        }
        do {
            switch try await loadContent(item.id) {
            case .text(let text):
                return .text(text)
            case .binary(let data, let typeIdentifier):
                return .binary(data: data, typeIdentifier: typeIdentifier)
            case .fileReferences(let paths):
                return .fileReferences(paths)
            case nil:
                return .unavailable
            }
        } catch {
            return .unavailable
        }
    }
}
