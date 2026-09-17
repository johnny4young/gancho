import Foundation
import GanchoKit

/// When the Library's saved-filter scope must rerun because local history
/// moved under it. A saved filter is a live predicate, so a capture that
/// matches it (or a deletion, an edit, a pin flip on a shown row) has to show
/// without the user switching scopes; the paged scopes keep their pages and
/// reconcile on their own next request instead.
public enum LibraryScopeReload {
    public static func isNeeded(
        savedFilterSelected: Bool, previous: [ClipItem], current: [ClipItem]
    ) -> Bool {
        guard savedFilterSelected else { return false }
        return signature(previous) != signature(current)
    }

    /// Identity plus the metadata a filter can see; use counters and
    /// `lastUsedAt` alone never trigger a reload.
    private static func signature(_ items: [ClipItem]) -> Set<String> {
        Set(
            items.map {
                "\($0.id.uuidString)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.isPinned)"
            })
    }
}
