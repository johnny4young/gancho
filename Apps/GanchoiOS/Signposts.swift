import OSLog

/// Content-free performance signposts for Instruments — the iOS twin of the
/// macOS helper (duplicated on purpose: signposts belong to app targets, so
/// no shared engine module may own this). The API accepts NOTHING beyond the
/// closed enum — no strings, no values — and the hygiene gate
/// (`SignpostHygieneTests`) rejects any signpost use outside this file.
enum Signpost {
    /// Capture accepted to the durable insert landing.
    case captureToInsert
    /// Query change to results applied.
    case queryToResults

    private static let signposter = OSSignposter(
        subsystem: "com.johnny4young.gancho.ios", category: "perf")

    func begin() -> OSSignpostIntervalState {
        switch self {
        case .captureToInsert:
            Self.signposter.beginInterval("capture-to-insert")
        case .queryToResults:
            Self.signposter.beginInterval("query-to-results")
        }
    }

    func end(_ state: OSSignpostIntervalState) {
        switch self {
        case .captureToInsert:
            Self.signposter.endInterval("capture-to-insert", state)
        case .queryToResults:
            Self.signposter.endInterval("query-to-results", state)
        }
    }
}
