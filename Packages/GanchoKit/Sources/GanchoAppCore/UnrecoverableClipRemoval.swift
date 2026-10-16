import Foundation
import GanchoKit

/// Removes clips whose payload this device's key cannot open, from this device
/// only. An identity reset also clears sync system fields, so a flagged row may
/// still have a good iCloud copy: no tombstone or CloudKit deletion is queued.
public struct UnrecoverableClipRemoval: Sendable {
    public init() {}

    /// Rescans first, so a clip healed by a re-capture since the count is kept.
    /// Nil when the scan fails and nothing was attempted.
    public func remove(
        scanner: any StoreMaintaining, store: any ClipboardStore
    ) async -> ClipDeletionWorkflow.Outcome? {
        guard let ids = try? await scanner.unrecoverableLocalClipIDs() else { return nil }
        return await ClipDeletionWorkflow().delete(
            ids: ids, store: store, syncStore: nil, engine: NoopSyncEngine(),
            syncEnabled: false)
    }
}
