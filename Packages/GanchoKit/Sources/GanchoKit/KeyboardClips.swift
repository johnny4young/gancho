import Foundation

/// Builds the keyboard's clip list: pinned (synced) clips first, then recent
/// history with the pinned ones removed so nothing appears twice.
///
/// Sensitive clips are EXCLUDED entirely (not just masked): the keyboard
/// inserts content into other apps, and offering to paste a secret the user
/// can't preview is a footgun. Secrets stay reachable through the app's
/// normal copy, never the keyboard.
public enum KeyboardClips {
    public static func ordered(
        pinned: [ClipItem], recent: [ClipItem], recentLimit: Int = 20
    ) -> [WidgetClipEntry] {
        let safePinned = pinned.filter { !$0.isSensitive }
        let pinnedIDs = Set(safePinned.map(\.id))
        let safeRecent = recent.filter { !$0.isSensitive && !pinnedIDs.contains($0.id) }
        return WidgetClips.entries(from: safePinned, limit: safePinned.count)
            + WidgetClips.entries(from: Array(safeRecent.prefix(recentLimit)), limit: recentLimit)
    }
}
