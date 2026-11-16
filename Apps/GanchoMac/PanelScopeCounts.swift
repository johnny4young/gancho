import Foundation
import GanchoKit

/// Clip totals behind the panel's rail: every visible clip, each board's
/// visible members and each kind's clips, counted like the panel's own list.
struct PanelScopeCounts: Equatable {
    var total: Int?
    var boards: [UUID: Int] = [:]
    /// Nil until the store answers.
    var kinds: [ClipContentKind: Int]?
}

/// Recounts when the boards change, a clip arrives or goes, the store reports
/// a change (a committed delete, board membership), a delete is pending or
/// undone, or the panel opens.
struct PanelScopeCountsKey: Equatable {
    let boardIDs: [UUID]
    let newest: UUID?
    let recentCount: Int
    let storeRevision: Int
    let pendingDeletions: Set<UUID>
    let opened: Int
}
