import OSLog

/// Content-free performance signposts for Instruments. The API accepts
/// NOTHING beyond the closed enum — no strings, no values — so an interval
/// can never carry clipboard-adjacent data, and names stay static (each case
/// maps to a `StaticString` literal, which `OSSignposter` requires anyway).
/// The hygiene gate (`SignpostHygieneTests`) rejects any signpost use outside
/// this file; signposts live in app targets only, never engine modules.
enum Signpost {
    /// App launch to the durable store being ready.
    case launchToStoreReady
    /// Panel requested to its first visible frame (the <100ms warm SLO).
    case panelToFirstFrame
    /// Query change to results applied.
    case queryToResults
    /// Paste action to the paste event being dispatched.
    case pasteDispatch

    private static let signposter = OSSignposter(
        subsystem: "com.johnny4young.gancho", category: "perf")

    func begin() -> OSSignpostIntervalState {
        switch self {
        case .launchToStoreReady:
            Self.signposter.beginInterval("launch-to-store-ready")
        case .panelToFirstFrame:
            Self.signposter.beginInterval("panel-to-first-frame")
        case .queryToResults:
            Self.signposter.beginInterval("query-to-results")
        case .pasteDispatch:
            Self.signposter.beginInterval("paste-dispatch")
        }
    }

    func end(_ state: OSSignpostIntervalState) {
        switch self {
        case .launchToStoreReady:
            Self.signposter.endInterval("launch-to-store-ready", state)
        case .panelToFirstFrame:
            Self.signposter.endInterval("panel-to-first-frame", state)
        case .queryToResults:
            Self.signposter.endInterval("query-to-results", state)
        case .pasteDispatch:
            Self.signposter.endInterval("paste-dispatch", state)
        }
    }
}
