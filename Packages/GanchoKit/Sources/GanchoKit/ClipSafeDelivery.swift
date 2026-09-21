import Foundation

/// Lazy delivery for surfaces without a protected-content reveal step (drag,
/// keyboard, sharing). Ordinary explicit app copy/reveal keeps its own policy.
public enum ClipSafeDelivery {
    public struct Payload: Sendable {
        public let item: ClipItem
        public let content: ClipContent
    }

    public static func isEligible(_ item: ClipItem, now: Date = .now) -> Bool {
        !ClipSafePresentation.requiresMasking(item)
            && (item.expiresAt.map { $0 > now } ?? true)
    }

    /// Read metadata before touching the payload, then reject a changed,
    /// deleted, expired or newly protected row after the asynchronous read.
    /// All failures collapse to unavailable: callers must not export a store
    /// error (which can contain query details) through an OS item provider.
    public static func load(
        id: UUID,
        metadata: @Sendable (UUID) async throws -> ClipItem?,
        content: @Sendable (UUID) async throws -> ClipContent?,
        now: @Sendable () -> Date = { .now }
    ) async -> Payload? {
        do {
            guard !Task.isCancelled,
                let before = try await metadata(id), isEligible(before, now: now()),
                let content = try await content(id),
                let after = try await metadata(id), before == after,
                isEligible(after, now: now()), !Task.isCancelled
            else { return nil }
            return Payload(item: after, content: content)
        } catch {
            return nil
        }
    }
}
