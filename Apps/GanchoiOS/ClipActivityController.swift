// ActivityKit's Activity isn't Sendable-annotated, so calling its nonisolated
// async update/end from this MainActor type trips strict-concurrency sending
// checks. @preconcurrency treats the SDK as pre-Swift-6 for those types.
@preconcurrency import ActivityKit
import Foundation
import GanchoKit

/// Owns the "ready to paste" Live Activity: starts it when a clip is captured,
/// keeps its sync badge current as the engine reports progress, and ends it on
/// request. iOS can't paste into other apps, so this glanceable surface — the
/// Dynamic Island and lock screen — is how a fresh clip announces itself.
/// Sensitive clips are masked before they're handed in, so a secret never
/// reaches the lock screen.
@MainActor
final class ClipActivityController {
    private var activity: Activity<ClipActivityAttributes>?
    /// The activity goes stale (and the system can retire it) ~30 min after the
    /// last clip, so a forgotten clip doesn't linger on the lock screen forever.
    private let staleAfter: TimeInterval = 30 * 60

    /// Whether the user has Live Activities turned on for Gancho.
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Start (or refresh) the activity for the just-captured clip.
    func show(_ item: ClipItem, sync: ClipSyncBadge) {
        guard isAvailable else { return }
        let content = ActivityContent(state: state(for: item, sync: sync), staleDate: staleDate)
        if let activity {
            Task { await activity.update(content) }
        } else {
            activity = try? Activity.request(
                attributes: ClipActivityAttributes(), content: content, pushType: nil)
        }
    }

    /// Update only the sync badge of a live activity (no-op when none is showing
    /// or the badge is unchanged).
    func updateSync(_ sync: ClipSyncBadge) {
        guard let activity else { return }
        var state = activity.content.state
        guard state.sync != sync else { return }
        state.sync = sync
        let content = ActivityContent(state: state, staleDate: staleDate)
        Task { await activity.update(content) }
    }

    /// Dismiss the activity immediately.
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func state(
        for item: ClipItem, sync: ClipSyncBadge
    )
        -> ClipActivityAttributes.ContentState
    {
        ClipActivityAttributes.ContentState(
            preview: item.isSensitive ? "•••" : String(item.preview.prefix(120)),
            kindSymbolName: item.kind.symbolName,
            isSensitive: item.isSensitive,
            sync: sync)
    }

    private var staleDate: Date { Date.now.addingTimeInterval(staleAfter) }
}
