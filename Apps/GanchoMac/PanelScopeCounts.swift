import Foundation

/// Clip totals behind the panel's scope chips: every visible clip, and each
/// board's members (the same counts the Library shows).
struct PanelScopeCounts: Equatable {
    var total: Int?
    var boards: [UUID: Int] = [:]
}

/// Recounts when the boards change, a clip arrives or goes, or the panel opens.
struct PanelScopeCountsKey: Equatable {
    let boardIDs: [UUID]
    let newest: UUID?
    let recentCount: Int
    let opened: Int
}
