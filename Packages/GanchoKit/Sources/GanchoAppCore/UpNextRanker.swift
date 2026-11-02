import Foundation
import GanchoKit

/// The clip Up next offers for the app in front, and why.
public struct UpNextPrediction: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        case pastedToday(Int)
        case pastedRecently(Int)
    }

    public let clipID: UUID
    public let reason: Reason

    public init(clipID: UUID, reason: Reason) {
        self.clipID = clipID
        self.reason = reason
    }
}

/// Same front app + recency + frequency, no model: each paste into the app
/// scores by its age, halving every few days.
public enum UpNextRanker {
    /// One paste is a coincidence; two into the same app is a habit.
    public static let minimumPastes = 2
    static let halfLife: TimeInterval = 3 * 24 * 60 * 60

    /// `events` are pastes into one app inside the log's window.
    public static func predict(
        _ events: [PasteEvent], now: Date, calendar: Calendar = .current
    ) -> UpNextPrediction? {
        struct Tally {
            var score = 0.0
            var count = 0
            var today = 0
            var latest = Date.distantPast
        }
        var tallies: [UUID: Tally] = [:]
        for event in events {
            var tally = tallies[event.clipID] ?? Tally()
            let age = max(now.timeIntervalSince(event.pastedAt), 0)
            tally.score += pow(0.5, age / halfLife)
            tally.count += 1
            if calendar.isDate(event.pastedAt, inSameDayAs: now) { tally.today += 1 }
            tally.latest = max(tally.latest, event.pastedAt)
            tallies[event.clipID] = tally
        }
        let best = tallies.filter { $0.value.count >= minimumPastes }.max { lhs, rhs in
            if lhs.value.score != rhs.value.score { return lhs.value.score < rhs.value.score }
            if lhs.value.latest != rhs.value.latest { return lhs.value.latest < rhs.value.latest }
            return lhs.key.uuidString > rhs.key.uuidString
        }
        guard let best else { return nil }
        let tally = best.value
        return UpNextPrediction(
            clipID: best.key,
            reason: tally.today >= minimumPastes
                ? .pastedToday(tally.today) : .pastedRecently(tally.count))
    }
}

/// Up next shows on the plain recent list only, never over its own first row,
/// and never while previews are hidden.
public struct UpNextVisibility: Equatable, Sendable {
    public var isEnabled: Bool
    public var previewsHidden: Bool
    public var isBrowsing: Bool
    public var firstRowID: UUID?

    public init(isEnabled: Bool, previewsHidden: Bool, isBrowsing: Bool, firstRowID: UUID?) {
        self.isEnabled = isEnabled
        self.previewsHidden = previewsHidden
        self.isBrowsing = isBrowsing
        self.firstRowID = firstRowID
    }

    public func shows(_ clipID: UUID) -> Bool {
        isEnabled && !previewsHidden && isBrowsing && firstRowID != clipID
    }
}

/// Runs writes one after another in the order they were asked for, so an erase
/// asked after a write always lands after it.
@MainActor
public final class OrderedWrites {
    private var tail: Task<Void, Never>?

    public init() {}

    public func enqueue(_ write: @escaping @Sendable () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await write()
        }
    }

    /// Waits for every write asked for so far.
    public func drain() async {
        await tail?.value
    }
}
