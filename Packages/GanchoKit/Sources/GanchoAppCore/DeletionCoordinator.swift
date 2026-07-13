import Foundation
import Observation

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
    /// The per-id grace timers, so a repeated delete or an Undo can cancel the
    /// prior one. Mirrors the shell's former `deletionTasks`. Not observed — it
    /// is bookkeeping, and Tasks are not a view input.
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

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
    public func beginDeletion(
        _ id: UUID,
        performDelete: @escaping @MainActor (UUID) async -> Void,
        didFinish: @escaping @MainActor (UUID) async -> Void
    ) {
        pending.insert(id)
        tasks[id]?.cancel()
        let grace = grace
        tasks[id] = Task { [weak self] in
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard pending.contains(id) else { return }
            tasks[id] = nil
            await performDelete(id)
            pending.remove(id)
            await didFinish(id)
        }
    }

    /// Reverses a pending delete before its window closes: cancel and drop the
    /// timer, clear the hold, then run `then` (the shell refreshes so the clip —
    /// still in the store — reappears in place). Mirrors the former `undoDelete`.
    public func undo(_ id: UUID, then: @escaping @MainActor (UUID) async -> Void) {
        tasks[id]?.cancel()
        tasks[id] = nil
        pending.remove(id)
        Task { await then(id) }
    }
}
