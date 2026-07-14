import Foundation
import GanchoKit

/// Content handed to a preview surface. Keeping loading policy in the shared
/// core makes every caller fail closed for sensitive kinds while preserving the
/// original payload only in memory after an explicit reveal.
public enum ClipPreviewPayload: Sendable, Equatable {
    case masked(String)
    case text(String)
    case binary(data: Data, typeIdentifier: String)
    case fileReferences([String])
    case unavailable
}

/// Lazily resolves one clip's full content only after the user asks for a
/// preview. Sensitive or intrinsically masked kinds return a canonical mask
/// without touching the content store unless the caller records an explicit
/// reveal interaction.
public struct ClipPreviewLoader: Sendable {
    public init() {}

    public func load(
        _ item: ClipItem,
        revealMaskedContent: Bool = false,
        loadContent: @Sendable (UUID) async throws -> ClipContent?
    ) async -> ClipPreviewPayload {
        guard revealMaskedContent || !ClipSafePresentation.requiresMasking(item) else {
            return .masked(ClipSafePresentation.masked)
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
