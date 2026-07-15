import Foundation
import Observation

/// One reversible delete operation. A transaction can carry one clip (the
/// historical path) or a visible-order batch, but it always owns one grace
/// timer and one Undo action.
public struct DeletionTransaction: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let clipIDs: [UUID]

    fileprivate init(id: UUID = UUID(), clipIDs: [UUID]) {
        self.id = id
        self.clipIDs = clipIDs
    }
}

/// Owns the macOS undo-window deletion STATE MACHINE that used to be inlined in
/// `AppModel` (`pendingDeletionIDs`/`deletionTasks` plus `delete`/`undoDelete`/
/// `commitDeletion`): the pending set, the per-id grace timer, and the
/// "commit only if still pending" boundary check. Pulling it into the package
/// makes the timing/state logic reachable by `swift test` for the first time —
/// it lives in an app target today and cannot be exercised.
///
/// `ReuseController` owns the immediate recent-list update and post-commit
/// reconciliation. The platform shell keeps the user-facing Undo toast and
/// supplies the concrete sync-aware store mutation as a closure. iOS deletes
/// immediately (no undo window) and does not use this type.
///
/// The grace is injectable so tests drive the commit deterministically instead
/// of waiting the real window; production keeps the shell's `.seconds(6)`.
///
/// Explicitly `@MainActor`: the extracted bodies ran on the shell's main actor,
/// and SwiftPM targets do not default to main-actor isolation the way the app
/// targets do. Annotating it preserves the execution context — and the ordering
/// against the shell's own main-actor state — exactly as it was, without an
/// AppKit/UIKit import.
@Observable
@MainActor
public final class DeletionCoordinator {
    /// Clips whose delete is in the undo window: still on disk, but held out of
    /// the list until the grace commits (or an Undo reclaims them). Mirrors the
    /// shell's former `pendingDeletionIDs`. Observable so a list can hide a clip
    /// the instant its delete begins (and show it again on Undo) — reading
    /// `isPending`/`hasPending` from a SwiftUI body tracks this set.
    private var pending: Set<UUID> = []
    /// One grace timer per user-visible transaction. Not observed — it is
    /// bookkeeping, and Tasks are not a view input.
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var transactions: [UUID: DeletionTransaction] = [:]
    /// Creation order per transaction. `transactions` is a Dictionary, whose
    /// iteration order is not stable, so folding overlapping transactions must
    /// sort by this — otherwise the folded `clipIDs` order (and with it the
    /// delete/undo order) would vary run to run, breaking the visible-order
    /// batch guarantee.
    @ObservationIgnored private var sequences: [UUID: UInt64] = [:]
    @ObservationIgnored private var nextSequence: UInt64 = 0

    /// The undo window length. Injectable so tests need not wait real seconds;
    /// the default is the shell's production value.
    private let grace: Duration

    public init(grace: Duration = .seconds(6)) {
        self.grace = grace
    }

    /// Whether `id`'s delete is still in its undo window — drives the reuse
    /// controller's per-row filter in `refreshRecents`.
    public func isPending(_ id: UUID) -> Bool {
        pending.contains(id)
    }

    /// Whether any delete is pending — lets the reuse controller skip the filter
    /// entirely when the list is unfiltered (the former
    /// `pendingDeletionIDs.isEmpty`).
    public var hasPending: Bool {
        !pending.isEmpty
    }

    /// Begins a deferred, reversible delete: marks `id` pending, cancels any
    /// prior timer for it (a repeated delete restarts the window), and schedules
    /// the commit after the grace. If the app quits mid-window the commit never
    /// runs, so the clip is kept (safe) — exactly as the shell's inlined task.
    ///
    /// CRITICAL ORDER, preserved from the original `commitDeletion`: a late Undo
    /// may reclaim the clip at the window boundary, so re-check `pending` first;
    /// then drop the timer, run the store delete, remove from `pending`, and only
    /// THEN fire `didFinish`. The remove happens BEFORE `didFinish` on purpose —
    /// the shell's `didFinish` reconciles the list from the store of record, so a
    /// FAILED store delete honestly reappears while a mid-commit refresh cannot
    /// flash the clip back (it stays filtered until the delete lands).
    @discardableResult
    public func beginDeletion(
        _ id: UUID,
        performDelete: @escaping @MainActor (UUID) async -> Void,
        didFinish: @escaping @MainActor (UUID) async -> Void
    ) -> DeletionTransaction {
        beginDeletion(
            [id],
            performDelete: { ids in
                guard let id = ids.first else { return }
                await performDelete(id)
            },
            didFinish: { ids in
                guard let id = ids.first else { return }
                await didFinish(id)
            })
    }

    /// Begins one reversible batch. Every id hides immediately, then the whole
    /// visible-order group commits behind one timer. If a requested id already
    /// belongs to a pending transaction, that transaction is folded into this
    /// one and its window restarts; no clip is accidentally released.
    ///
    /// Folding is deterministic: older pending transactions contribute their
    /// clips first (in their own visible order), then the newly requested ids.
    @discardableResult
    public func beginDeletion(
        _ ids: [UUID],
        performDelete: @escaping @MainActor ([UUID]) async -> Void,
        didFinish: @escaping @MainActor ([UUID]) async -> Void
    ) -> DeletionTransaction {
        let requested = unique(ids)
        guard !requested.isEmpty else { return DeletionTransaction(clipIDs: []) }

        let requestedSet = Set(requested)
        let overlapping = transactions.values
            .filter { !requestedSet.isDisjoint(with: $0.clipIDs) }
            .sorted { (sequences[$0.id] ?? 0) < (sequences[$1.id] ?? 0) }
        var combined = overlapping.flatMap(\.clipIDs)
        combined.append(contentsOf: requested)
        let clipIDs = unique(combined)
        for transaction in overlapping {
            tasks[transaction.id]?.cancel()
            tasks[transaction.id] = nil
            transactions[transaction.id] = nil
            sequences[transaction.id] = nil
            pending.subtract(transaction.clipIDs)
        }

        let transaction = DeletionTransaction(clipIDs: clipIDs)
        transactions[transaction.id] = transaction
        sequences[transaction.id] = nextSequence
        nextSequence += 1
        pending.formUnion(clipIDs)
        let grace = grace
        tasks[transaction.id] = Task { [weak self] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard transactions[transaction.id] != nil else { return }
            tasks[transaction.id] = nil
            await performDelete(transaction.clipIDs)
            pending.subtract(transaction.clipIDs)
            transactions[transaction.id] = nil
            sequences[transaction.id] = nil
            await didFinish(transaction.clipIDs)
        }
        return transaction
    }

    /// Reverses a pending delete before its window closes: cancel and drop the
    /// timer, clear the hold, then run `then` (the shell refreshes so the clip —
    /// still in the store — reappears in place). Mirrors the former `undoDelete`.
    public func undo(_ id: UUID, then: @escaping @MainActor (UUID) async -> Void) {
        guard let transaction = transactions.values.first(where: { $0.clipIDs.contains(id) }) else {
            return
        }
        undo(transaction) { _ in
            await then(id)
        }
    }

    /// Reverses every clip in one pending transaction with one user action.
    public func undo(
        _ transaction: DeletionTransaction,
        then: @escaping @MainActor ([UUID]) async -> Void
    ) {
        guard let current = transactions[transaction.id] else { return }
        tasks[current.id]?.cancel()
        tasks[current.id] = nil
        transactions[current.id] = nil
        sequences[current.id] = nil
        pending.subtract(current.clipIDs)
        Task { await then(current.clipIDs) }
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
