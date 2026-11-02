// ActivityKit's Activity isn't Sendable-annotated, so calling its nonisolated
// async update/end from this MainActor type trips strict-concurrency sending
// checks. @preconcurrency treats the SDK as pre-Swift-6 for those types.
@preconcurrency import ActivityKit
import Foundation
import GanchoKit
import UIKit

/// Raises the "ready to paste" Live Activity when a clip is captured or copied.
/// It's deliberately transient: a short, self-dismissing nudge — not a resident
/// of the Dynamic Island. iOS can't watch the pasteboard from other apps in the
/// background, so this only fires from inside Gancho. Sensitive clips are masked
/// before they're handed in, so a secret never reaches the lock screen.
@MainActor
final class ClipActivityController {
    /// How long "ready to paste" stays up before it dismisses itself. Short, so
    /// it reads as a momentary confirmation rather than an always-on banner.
    private let visibleFor: TimeInterval = 3 * 60

    /// Whether the user has Live Activities turned on for Gancho.
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Show the just-captured/copied clip, replacing any one already up, and
    /// schedule its own dismissal so it doesn't linger.
    func show(_ item: ClipItem, sync: ClipSyncBadge) {
        guard isAvailable else { return }
        // The widgets' masking rule: masked kinds stay masked even when the
        // row's sensitive flag is missing.
        let masked = ClipSafePresentation.requiresMasking(item)
        let state = ClipActivityAttributes.ContentState(
            preview: String(ClipSafePresentation.displayText(for: item).prefix(120)),
            kindSymbolName: item.kind.symbolName,
            isSensitive: masked,
            sync: sync,
            clipID: item.id)
        // The change count, never the content: a different one later means
        // something else was copied, and "ready to paste" is over.
        WidgetState.readyChangeCount = UIPasteboard.general.changeCount
        let dismissAt = Date.now.addingTimeInterval(visibleFor)
        let content = ActivityContent(state: state, staleDate: dismissAt)
        Task {
            await endAll(.immediate)
            guard
                let activity = try? Activity.request(
                    attributes: ClipActivityAttributes(), content: content, pushType: nil)
            else { return }
            // End it with a future dismissal: the system removes it after the
            // window even while Gancho is backgrounded (the user is pasting in
            // another app), so it never becomes a permanent fixture.
            await activity.end(content, dismissalPolicy: .after(dismissAt))
        }
    }

    /// Ends "ready to paste" when the pasteboard changed since it went up,
    /// the closest iOS lets Gancho come to seeing the next copy elsewhere.
    func endIfPasteboardChanged() {
        guard let shown = WidgetState.readyChangeCount,
            shown != UIPasteboard.general.changeCount
        else { return }
        WidgetState.readyChangeCount = nil
        end()
    }

    /// Dismiss any live activity immediately.
    func end() {
        Task { await endAll(.immediate) }
    }

    private func endAll(_ policy: ActivityUIDismissalPolicy) async {
        for activity in Activity<ClipActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: policy)
        }
    }
}
