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
        case emptyContent
        case notEditable
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

    /// Saves an exact user-authored text body. Blank drafts are rejected;
    /// leading whitespace and line endings otherwise remain untouched. Binary,
    /// file-reference, structured-color, and sensitive rows are read-only. The
    /// store repeats those guards atomically so a row that changes while the
    /// editor is open cannot be overwritten.
    public func updateText<Store>(
        _ item: ClipItem,
        text: String,
        store: Store,
        engine: any SyncEngine
    ) async -> Outcome where Store: ClipReading & ClipEnriching {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .emptyContent
        }
        do {
            guard let authoritative = try await store.item(id: item.id) else {
                return .clipUnavailable
            }
            guard !authoritative.isSensitive, authoritative.kind.allowsTextEditing,
                case .text(let storedText)? = try await store.content(for: item.id)
            else { return .notEditable }
            guard storedText != text else { return .unchanged }
            try await store.updateClipText(id: item.id, text: text)
            await engine.enqueue([authoritative])
            return .saved
        } catch {
            return .failed
        }
    }
}
