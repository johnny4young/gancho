import Foundation
import GanchoKit

/// Pure filtering for the panel's ⌘B board picker, so the match / create-offer
/// decisions are unit-tested without the SwiftUI overlay.
public enum BoardPickerFilter {
    /// Boards whose name contains `query` (case-insensitive); all boards when the
    /// query is empty. Order is preserved from the input.
    public static func matches(_ boards: [Pinboard], query: String) -> [Pinboard] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return boards }
        return boards.filter { $0.name.lowercased().contains(needle) }
    }

    /// Whether `query` names a NEW board — non-empty and not an exact
    /// (case-insensitive) name of an existing board. Drives the "Create '<name>'"
    /// row so ⌘Return can file the clip into a board it just named.
    public static func canCreate(_ boards: [Pinboard], query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !boards.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}
