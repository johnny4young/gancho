import Foundation
import GanchoKit

/// Shared durable ordering for user-authored clip metadata edits.
///
/// Platform views own draft state and presentation. This controller normalizes
/// the title, resolves the authoritative row, performs the local write, and
/// only then schedules sync. It keeps macOS and iOS from diverging on empty
/// titles, stale rows, or enqueue-before-persistence behavior.
public struct ClipEditingController: Sendable {
    public enum Outcome: Sendable, Equatable {
        case saved
        case unchanged
        case clipUnavailable
        case failed
    }

    public init() {}

    /// Saves a user-authored title. Leading/trailing whitespace is discarded;
    /// an all-whitespace draft intentionally clears the title. No-op edits do
    /// not write or enqueue, and failed writes never reach the sync engine.
    public func updateTitle<Store>(
        _ item: ClipItem,
        title: String,
        store: Store,
        engine: any SyncEngine
    ) async -> Outcome where Store: ClipReading & ClipEnriching {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            guard let authoritative = try await store.item(id: item.id) else {
                return .clipUnavailable
            }
            guard authoritative.title != normalized else { return .unchanged }
            try await store.updateTitle(id: item.id, title: normalized)
            await engine.enqueue([item])
            return .saved
        } catch {
            return .failed
        }
    }
}
