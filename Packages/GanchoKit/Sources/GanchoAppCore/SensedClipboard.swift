import Foundation
import GanchoKit

/// What the iPhone's pasteboard card can name without reading anything: the
/// kind the system's detect hints point at.
public enum SensedClipboard: Equatable, Sendable {
    case empty, link, searchText, number, other

    public init(hasContent: Bool, probableWebURL: Bool, probableWebSearch: Bool, number: Bool) {
        if !hasContent {
            self = .empty
        } else if probableWebURL {
            self = .link
        } else if probableWebSearch {
            self = .searchText
        } else if number {
            self = .number
        } else {
            self = .other
        }
    }

    public var symbolName: String {
        switch self {
        case .empty, .other: "doc.on.clipboard"
        case .link: "link"
        case .searchText: "magnifyingglass"
        case .number: "number"
        }
    }

    /// The row tint family: a link reads as one, everything else stays neutral.
    public var tintKind: ClipContentKind { self == .link ? .url : .text }
}

/// A save from the Paste button that the card can open for a short while.
public struct RecentPasteSave: Equatable, Sendable {
    public static let openWindow: TimeInterval = 4

    public let clipID: UUID
    public let changeCount: Int
    public let savedAt: Date
    public let window: TimeInterval

    public init(
        clipID: UUID, changeCount: Int, savedAt: Date, window: TimeInterval = Self.openWindow
    ) {
        self.clipID = clipID
        self.changeCount = changeCount
        self.savedAt = savedAt
        self.window = window
    }

    /// Only within the window, and only while the same copy is on the pasteboard.
    public func offersOpen(now: Date, currentChangeCount: Int) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return age >= 0 && age < window && currentChangeCount == changeCount
    }
}
