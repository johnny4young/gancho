import Foundation
import GanchoKit

/// Loads the exact snippet revision the user selected or reviewed. A delayed
/// read or a second insertion after filling fields cannot silently substitute
/// a different template, a deleted row, or newly protected content.
public struct SnippetBodyLoader: Sendable {
    public init() {}

    public func load(
        _ snippet: ClipItem,
        metadata: @Sendable (UUID) async throws -> ClipItem?,
        content: @Sendable (UUID) async throws -> ClipContent?
    ) async -> String? {
        let expected = ClipContentVersion(snippet)
        let payload = await ClipSafeDelivery.load(
            id: snippet.id,
            metadata: { id in
                guard let current = try await metadata(id), ClipContentVersion(current) == expected
                else { return nil }
                return current
            }, content: content)
        guard case .text(let body) = payload?.content else { return nil }
        return body
    }
}
