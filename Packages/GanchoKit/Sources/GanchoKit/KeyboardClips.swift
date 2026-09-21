import Foundation

/// Builds the keyboard's clip list: pinned (synced) clips first, then recent
/// history with the pinned ones removed so nothing appears twice.
///
/// Sensitive clips are EXCLUDED entirely (not just masked): the keyboard
/// inserts content into other apps, and offering to paste a secret the user
/// can't preview is a footgun. Secrets stay reachable through the app's
/// normal copy, never the keyboard.
public enum KeyboardClips {
    /// Filter before the store's LIMIT, so hidden rows cannot starve safe
    /// results. Empty-text search preserves pinned-first capture-time order.
    public static func query(text: String = "", boardID: UUID? = nil) -> ClipSearchQuery {
        ClipSearchQuery(
            text: text,
            kinds: Set(
                ClipContentKind.allCases.filter {
                    !ClipSafePresentation.requiresMasking(kind: $0, isSensitive: false)
                }),
            boardID: boardID, excludesSensitive: true)
    }

    public static func ordered(
        pinned: [ClipItem], recent: [ClipItem], recentLimit: Int = 20
    ) -> [WidgetClipEntry] {
        let safePinned = pinned.filter { !ClipSafePresentation.requiresMasking($0) }
        let pinnedIDs = Set(safePinned.map(\.id))
        let safeRecent = recent.filter {
            !ClipSafePresentation.requiresMasking($0) && !pinnedIDs.contains($0.id)
        }
        return WidgetClips.entries(from: safePinned, limit: safePinned.count)
            + WidgetClips.entries(from: Array(safeRecent.prefix(recentLimit)), limit: recentLimit)
    }
}
