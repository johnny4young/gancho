import Foundation
import GanchoKit

/// Owns the board MUTATION logic both app shells used to inline (`AppModel`
/// and `IOSAppModel`'s create / rename / delete / membership methods): the
/// free-tier gate decision, the `createPinboard` + membership writes, and the
/// sync-enabled vs sync-off deletion split — over the `BoardStoring` facet and
/// the live `SyncEngine`. It is the single home for logic that had to be
/// bug-fixed twice and could not be reached by `swift test`.
///
/// The shells keep everything that is genuinely theirs, so no SwiftUI view
/// changes: the `@Observable` `boards` list, `refreshBoards()`/`refreshRecents`/
/// `search()` sequencing, `selectedBoardID` handling, name trimming/empty-guard,
/// the concrete-store nil-guard, and the paywall / toast / note UI. The two
/// shells had diverged only in those app-owned edges, surfaced here as:
/// - the free-tier gate UI, delivered through `onFreeLimit` (macOS opens the
///   paywall window; iOS bumps `proGateTick` or flashes a note);
/// - the post-create refresh, chosen by the caller off `BoardCreateOutcome`
///   (macOS refreshes even when the create fails, iOS's filing path only on
///   success) — so refresh stays in the shell, verbatim;
/// - the "added to board" toast, delivered through `onAssigned` (macOS only).
///
/// Only `BoardStoring` and the engine are needed: the gate counts boards via
/// `pinboards()`, never a `StoreStatsProviding` counter, so that facet is not
/// required here (verified against both shells' bodies).
///
/// Explicitly `@MainActor`: the extracted bodies ran inside the shells'
/// main-actor `Task`s, and SwiftPM targets do not default to main-actor
/// isolation the way the app targets do. Annotating it keeps the execution
/// context — and the ordering against the shells' own main-actor state — exactly
/// as it was, and keeps the type `swift test`-able without an AppKit/UIKit
/// import.
@MainActor
public struct BoardsController {
    public init() {}

    /// The three ways `createBoard` can end, so the caller reproduces its
    /// platform's exact post-create refresh without the controller touching the
    /// shell's `boards`/`refreshRecents`/`search`:
    /// - `blocked`: the free-tier gate stopped it (`onFreeLimit` already fired);
    /// - `failed`: `createPinboard` did not return a board;
    /// - `created`: success, carrying the new board's id (the iOS filing path
    ///   returns it so the move-to-board sheet can refresh its checkmarks).
    public enum BoardCreateOutcome: Sendable, Equatable {
        case blocked
        case failed
        case created(UUID)
    }

    /// Creates a board, honoring the free-tier gate, and — when `item` is set —
    /// files that clip into it, mirroring both shells' create bodies exactly:
    /// count non-system boards, gate, `createPinboard(name:sfSymbol:"square.stack")`,
    /// `enqueue(boards:)`, then (if filing) `assign` followed by `onAssigned`.
    ///
    /// - Parameters:
    ///   - name: the board name, already trimmed/empty-guarded by the shell so
    ///     each platform keeps its own trimming behavior (macOS does not trim,
    ///     iOS does — both preserved by doing it caller-side).
    ///   - item: the clip to file into the new board, or nil for a plain create.
    ///   - store: the board write surface.
    ///   - engine: the live sync engine (read fresh from the shell's
    ///     `SyncController` at the call site, since it is swapped on reconfigure).
    ///   - isPro: the entitlement input to `PinLimits.canCreatePinboard`.
    ///   - onFreeLimit: the platform's gate UI, run in the gate's original
    ///     position (macOS paywall; iOS `proGateTick`/note).
    ///   - onAssigned: run immediately after a successful `assign`, in the toast's
    ///     original position (macOS "Added to board"; iOS passes an empty hook).
    /// - Returns: the outcome, so the caller drives its own refresh.
    public func createBoard(
        name: String,
        filing item: ClipItem?,
        store: any BoardStoring,
        engine: any SyncEngine,
        isPro: Bool,
        onFreeLimit: () -> Void,
        onAssigned: () -> Void
    ) async -> BoardCreateOutcome {
        // The built-in Favorites board never counts against the free limit.
        let count = (try? await store.pinboards().filter { !$0.isSystem }.count) ?? 0
        guard PinLimits.canCreatePinboard(currentBoardCount: count, isPro: isPro) else {
            onFreeLimit()
            return .blocked
        }
        guard let board = try? await store.createPinboard(name: name, sfSymbol: "square.stack")
        else { return .failed }
        await engine.enqueue(boards: [board])
        if let item {
            try? await store.assign(clipID: item.id, toBoard: board.id)
            onAssigned()
        }
        return .created(board.id)
    }

    /// Renames a user board and queues its new metadata for sync, mirroring both
    /// shells: `renameBoard`, then `enqueue(boards:)` with the locally updated
    /// copy. A guarded no-op on system boards (the store enforces `isSystem`);
    /// the shell still owns the trim and the follow-up refresh.
    public func renameBoard(
        _ board: Pinboard,
        name: String,
        store: any BoardStoring,
        engine: any SyncEngine
    ) async {
        try? await store.renameBoard(id: board.id, name: name)
        var renamed = board
        renamed.name = name
        await engine.enqueue(boards: [renamed])
    }

    /// Deletes a user board with the exact sync/no-sync split both shells used:
    /// when sync is on, tombstone via `deletePinboardForSync(id:now:.now)` and
    /// `enqueueBoardDeletion` so the removal reaches the other devices; otherwise
    /// a plain local `deletePinboard`. The `isSystem` guard, `selectedBoardID`
    /// clearing, and refresh stay in the shell.
    public func deleteBoard(
        _ board: Pinboard,
        store: any BoardStoring,
        engine: any SyncEngine,
        syncEnabled: Bool
    ) async {
        if syncEnabled {
            try? await store.deletePinboardForSync(id: board.id, now: .now)
            await engine.enqueueBoardDeletion(ids: [board.id])
        } else {
            try? await store.deletePinboard(id: board.id)
        }
    }

    /// Adds or removes a clip's membership in one board, mirroring both shells:
    /// `assign` when `member`, `unassign` otherwise. Membership rides the clip's
    /// sync record (no engine call here), so nothing is enqueued; the shell owns
    /// the follow-up refresh (`refreshRecents`/`search`).
    public func setBoardMembership(
        _ item: ClipItem,
        board: Pinboard,
        member: Bool,
        store: any BoardStoring
    ) async {
        if member {
            try? await store.assign(clipID: item.id, toBoard: board.id)
        } else {
            try? await store.unassign(clipID: item.id, fromBoard: board.id)
        }
    }
}
