import Foundation

/// One post-launch maintenance step: a named, individually-gated async unit of
/// housekeeping. The `name` is a stable, content-free label (for tests and any
/// future diagnostics) — never clip data. `isEnabled` lets a step be declared
/// unconditionally at the call site but skipped by a preference (the embedding
/// refresh only runs when semantic search is on), so the gating is visible in
/// the pipeline rather than hidden in an `if` around the call.
public struct MaintenanceStep: Sendable {
    public let name: String
    public let isEnabled: Bool
    public let operation: @Sendable () async -> Void

    public init(
        _ name: String, isEnabled: Bool = true,
        operation: @escaping @Sendable () async -> Void
    ) {
        self.name = name
        self.isEnabled = isEnabled
        self.operation = operation
    }
}

/// Runs the ordered post-launch maintenance pipeline that used to be an inline
/// `Task` in `AppModel.init` — the legacy-preview backfill, the optional
/// embedding refresh, and the Spotlight reconcile. Extracting it makes the two
/// properties that actually matter TESTABLE for the first time: the steps run
/// **in declared order** and a **disabled step is skipped** (so no one silently
/// reorders the reconcile before the backfill, or runs the embedding refresh
/// when semantic search is off). A step of the ongoing AppModel-facade
/// extraction.
///
/// Sequential by contract: each step is awaited before the next begins, because
/// the order is load-bearing (the reconcile should see the backfilled previews)
/// and running them at once would spike a launch that is deliberately kept off
/// the capture and first-panel paths. The shell still owns WHERE it runs (a
/// utility-priority task); the runner owns the SEQUENCE.
public struct MaintenanceRunner: Sendable {
    public init() {}

    /// Await each enabled step, in order. Returns the names of the steps that
    /// ran (enabled), for diagnostics and test assertions — content-free.
    @discardableResult
    public func run(_ steps: [MaintenanceStep]) async -> [String] {
        var ran: [String] = []
        for step in steps where step.isEnabled {
            await step.operation()
            ran.append(step.name)
        }
        return ran
    }
}
