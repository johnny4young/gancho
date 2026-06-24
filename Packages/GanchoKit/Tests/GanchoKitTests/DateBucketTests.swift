import Foundation
import Testing

@testable import GanchoKit

@Suite("DateBucket — semantic grouping")
struct DateBucketTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ year: Int, _ month: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: d, hour: 12))!
    }

    @Test("Each date lands in the expected bucket (mid-month now)")
    func buckets() {
        let now = day(2026, 6, 15)
        let c = calendar
        #expect(DateBucket.of(day(2026, 6, 15), now: now, calendar: c) == .today)
        #expect(DateBucket.of(day(2026, 6, 14), now: now, calendar: c) == .yesterday)
        #expect(DateBucket.of(day(2026, 6, 2), now: now, calendar: c) == .thisMonth)
        #expect(DateBucket.of(day(2026, 5, 20), now: now, calendar: c) == .lastMonth)
        #expect(DateBucket.of(day(2026, 2, 10), now: now, calendar: c) == .thisYear)
        #expect(DateBucket.of(day(2025, 11, 1), now: now, calendar: c) == .lastYear)
        #expect(DateBucket.of(day(2024, 3, 1), now: now, calendar: c) == .older)
    }

    @Test("January boundary: last month rolls into the previous year")
    func januaryBoundary() {
        let now = day(2026, 1, 10)
        let c = calendar
        #expect(DateBucket.of(day(2026, 1, 10), now: now, calendar: c) == .today)
        #expect(DateBucket.of(day(2025, 12, 20), now: now, calendar: c) == .lastMonth)
        #expect(DateBucket.of(day(2025, 6, 1), now: now, calendar: c) == .lastYear)
        #expect(DateBucket.of(day(2024, 12, 1), now: now, calendar: c) == .older)
    }

    @Test("Buckets stay contiguous over a createdAt-descending list")
    func contiguousOverSortedList() {
        let now = day(2026, 6, 15)
        let dates = [
            day(2026, 6, 15), day(2026, 6, 15),  // today ×2
            day(2026, 6, 14),  // yesterday
            day(2026, 6, 3),  // this month
            day(2026, 4, 1),  // this year
            day(2023, 1, 1),  // older
        ]
        let buckets = dates.map { DateBucket.of($0, now: now, calendar: calendar) }
        // Collapse to the sequence of runs; a contiguous grouping has no
        // bucket reappearing after a different one started.
        var runs: [DateBucket] = []
        for b in buckets where runs.last != b { runs.append(b) }
        #expect(Set(runs).count == runs.count, "a bucket reappeared — not contiguous")
        #expect(runs == [.today, .yesterday, .thisMonth, .thisYear, .older])
    }
}
