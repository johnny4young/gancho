import Foundation
import Testing

@testable import GanchoKit

@Suite("ClipSections — pinned-first grouping")
struct ClipSectionsTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    private func clip(_ created: Date, pinned: Bool = false) -> ClipItem {
        ClipItem(
            createdAt: created, preview: "c", contentHash: UUID().uuidString, isPinned: pinned)
    }

    @Test("Pinned clips form the first section; the rest group by date bucket")
    func grouping() {
        let now = day(2026, 6, 15)
        // Already ordered pinned-first, then createdAt desc (as recentForBrowse returns).
        let clips = [
            clip(day(2026, 6, 1), pinned: true),  // pinned (old date, still first)
            clip(day(2026, 4, 9), pinned: true),  // pinned
            clip(day(2026, 6, 15)),  // today
            clip(day(2026, 6, 15)),  // today
            clip(day(2026, 6, 14)),  // yesterday
            clip(day(2023, 1, 1)),  // older
        ]
        let groups = ClipSections.grouped(clips, now: now, calendar: calendar)
        #expect(
            groups.map(\.section) == [.pinned, .date(.today), .date(.yesterday), .date(.older)])
        #expect(groups.first?.clips.count == 2)
        #expect(groups.map(\.id).count == Set(groups.map(\.id)).count)  // ids unique
    }

    @Test("Empty input yields no sections")
    func empty() {
        #expect(ClipSections.grouped([], now: day(2026, 6, 15), calendar: calendar).isEmpty)
    }
}
