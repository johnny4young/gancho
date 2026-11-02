import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Up next ranker")
struct UpNextRankerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func pastes(_ id: UUID, ago: [TimeInterval]) -> [PasteEvent] {
        ago.map { PasteEvent(clipID: id, pastedAt: now.addingTimeInterval(-$0)) }
    }

    @Test("Below the minimum there is no prediction")
    func threshold() {
        let id = UUID()
        let once = pastes(id, ago: [60])
        #expect(UpNextRanker.predict(once, now: now, calendar: calendar) == nil)
        let enough = pastes(id, ago: Array(repeating: 60, count: UpNextRanker.minimumPastes))
        #expect(UpNextRanker.predict(enough, now: now, calendar: calendar)?.clipID == id)
        #expect(UpNextRanker.predict([], now: now, calendar: calendar) == nil)
    }

    @Test("Recent pastes outweigh more frequent old ones")
    func recencyBeatsStaleFrequency() {
        let recent = UUID()
        let stale = UUID()
        let events =
            pastes(recent, ago: [60, 120])
            + pastes(stale, ago: [20 * day, 21 * day, 22 * day, 23 * day])
        #expect(UpNextRanker.predict(events, now: now, calendar: calendar)?.clipID == recent)
    }

    @Test("At the same age, the more frequent clip wins")
    func frequencyBreaksEqualAge() {
        let often = UUID()
        let rarely = UUID()
        let events = pastes(often, ago: [day, day, day]) + pastes(rarely, ago: [day, day])
        #expect(UpNextRanker.predict(events, now: now, calendar: calendar)?.clipID == often)
    }

    @Test("The reason counts today's pastes, else the window's")
    func reason() {
        let id = UUID()
        let today = pastes(id, ago: [60, 120, 180])
        #expect(
            UpNextRanker.predict(today, now: now, calendar: calendar)?.reason == .pastedToday(3))

        let spread = pastes(id, ago: [60, 3 * day, 9 * day])
        #expect(
            UpNextRanker.predict(spread, now: now, calendar: calendar)?.reason
                == .pastedRecently(3))
    }

    @Test("An erase asked after a slow write lands after it")
    @MainActor
    func orderedWrites() async {
        actor Log {
            var entries: [String] = []
            func append(_ entry: String) { entries.append(entry) }
        }
        let log = Log()
        let writes = OrderedWrites()
        writes.enqueue {
            try? await Task.sleep(for: .milliseconds(50))
            await log.append("record")
        }
        writes.enqueue { await log.append("erase") }
        await writes.drain()
        #expect(await log.entries == ["record", "erase"])
    }

    @Test("Up next shows only on the plain list, with previews, off its first row")
    func visibility() {
        let clip = UUID()
        let shown = UpNextVisibility(
            isEnabled: true, previewsHidden: false, isBrowsing: true, firstRowID: UUID())
        #expect(shown.shows(clip))
        var off = shown
        off.isEnabled = false
        var hidden = shown
        hidden.previewsHidden = true
        var searching = shown
        searching.isBrowsing = false
        var firstRow = shown
        firstRow.firstRowID = clip
        for state in [off, hidden, searching, firstRow] { #expect(!state.shows(clip)) }
    }
}
