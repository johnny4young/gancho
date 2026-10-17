import Foundation
import GanchoKit

/// Removes clips whose payload this device's key cannot open, from this device
/// only. A flagged row may still have a good iCloud copy (an identity reset also
/// clears sync system fields), so no tombstone or CloudKit deletion is queued.
public struct UnrecoverableClipRemoval: Sendable {
    public init() {}

    /// Rescans first, so a clip healed since the count is kept.
    /// Nil when the scan fails and nothing was attempted.
    public func remove(scanner: any StoreMaintaining) async -> ClipDeletionWorkflow.Outcome? {
        guard let local = try? await scanner.unrecoverableLocalClipIDs(),
            let synced = try? await scanner.unrecoverableSyncedClipIDs()
        else { return nil }
        let ids = local + synced
        var failed: [UUID] = []
        for id in ids {
            do { try await scanner.deleteLocalOnly(id: id) } catch { failed.append(id) }
        }
        if failed.isEmpty { return .deleted(propagated: false) }
        return failed.count == ids.count ? .failed : .partial(failed: failed)
    }
}
