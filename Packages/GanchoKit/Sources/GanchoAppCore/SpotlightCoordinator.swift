import Foundation

/// Owns everything about keeping the curated-Library Spotlight domain fresh —
/// the state that used to be spread across `AppModel` as `refreshSpotlight`,
/// `startStoreChangeReconcilers`, and `reconcileSpotlightNow`, plus the
/// duplicate reconcile inlined in the launch maintenance task. One type now
/// holds the bus subscription, the debounce, and the single reconcile worker,
/// so the "donate curation to Spotlight" policy lives in one place the package
/// can unit-test — a step of the ongoing AppModel-facade extraction.
///
/// The reconcile itself is injected as a closure: the coordinator never sees
/// the store or the toggle, only "run the reconcile for the current state and
/// tell me whether it landed." The shell wires that closure to
/// `LibrarySpotlightService`; tests wire a counter. The reconcile is always a
/// full recompute-and-replace, so the coordinator never needs to know WHAT
/// changed — only that something relevant did.
@MainActor
public final class SpotlightCoordinator {
    /// The reconcile outcome the shell reports back: `nil` when there is no
    /// store yet (skip silently — not an error), `true` when the donation
    /// landed, `false` when the index write failed and the shell should note
    /// it. Kept off the coordinator so donation stays the shell's concern.
    public typealias ReconcileResult = Bool?

    private let coalescer: StoreChangeCoalescer
    private let reconcile: @MainActor () async -> ReconcileResult
    private let onFailure: @MainActor () -> Void
    private var task: Task<Void, Never>?

    /// No defaulted parameters on purpose: a `@MainActor` initializer cannot
    /// carry default-argument expressions without an isolation clash, so both
    /// call sites (the shell and the tests) pass the coalescer and failure sink
    /// explicitly. `SpotlightCoordinator.defaultCoalescer` is the shared one.
    public init(
        coalescer: StoreChangeCoalescer,
        reconcile: @escaping @MainActor () async -> ReconcileResult,
        onFailure: @escaping @MainActor () -> Void
    ) {
        self.coalescer = coalescer
        self.reconcile = reconcile
        self.onFailure = onFailure
    }

    /// The production debounce window — shared so the shell and tests that want
    /// real timing agree on one value. `nonisolated`, and it passes `sleep`
    /// EXPLICITLY rather than through `StoreChangeCoalescer`'s defaulted
    /// argument: a defaulted closure argument evaluated where the caller is
    /// `@MainActor` is what trips "default argument cannot be both main
    /// actor-isolated and nonisolated", so the production path uses no defaults.
    nonisolated public static var defaultCoalescer: StoreChangeCoalescer {
        StoreChangeCoalescer(window: .milliseconds(300), sleep: { try await Task.sleep(for: $0) })
    }

    /// Which coalesced changes make the curated Spotlight set stale. Snippets
    /// and pins ARE the donated set, so any `curation` change matters; a clip
    /// edit or delete (`clips`) can change or remove a donated row. A
    /// board-only burst never touches the curated domain, so it is skipped —
    /// this predicate is the whole "react to the right mutations" rule.
    static func reactsTo(_ batch: StoreChangeBatch) -> Bool {
        batch.contains(.curation) || batch.contains(.clips)
    }

    /// Subscribe to the bus and reconcile once per relevant debounced burst.
    /// Runs at utility priority off every interaction path; a 50-clip batch
    /// delete collapses (via the coalescer) into a single reconcile. Awaiting
    /// the reconcile in the loop also serializes them, so two bursts can never
    /// race overlapping index writes.
    public func start(subscribingTo bus: StoreChangeBus) {
        task?.cancel()
        let stream = bus.subscribe()
        let coalescer = self.coalescer
        task = Task(priority: .utility) { [weak self] in
            for await batch in coalescer.batches(of: stream) {
                guard let self else { return }
                guard Self.reactsTo(batch) else { continue }
                await self.reconcileNow()
            }
        }
    }

    /// Run the reconcile once for the current state and route a failure to the
    /// shell. The launch maintenance task calls this directly (after the
    /// backfill and embedding refresh) so the launch and bus-driven paths
    /// share ONE reconcile worker instead of the two copies they were before.
    public func reconcileNow() async {
        guard let landed = await reconcile() else { return }  // no store yet
        if !landed { onFailure() }
    }

    /// Stop reacting to the bus (the shell tears the coordinator down). Safe to
    /// call more than once.
    public func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
