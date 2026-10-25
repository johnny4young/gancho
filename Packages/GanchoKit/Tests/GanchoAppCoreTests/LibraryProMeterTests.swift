import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Library Pro meter and card age — read from the Free constants")
struct LibraryProMeterTests {
    @Test("The fill follows the fullest ceiling, clamped to one")
    func fraction() {
        let boards = PinLimits.freeMaxPinboards
        let snippets = SnippetLimits.freeMaxSnippets
        #expect(LibraryProMeter(boards: 0, pins: 0, snippets: 0).fraction == 0)
        let mostlyBoards = LibraryProMeter(boards: boards - 1, pins: 1, snippets: 1)
        #expect(mostlyBoards.fraction == Double(boards - 1) / Double(boards))
        let pinsFull = LibraryProMeter(boards: 0, pins: PinLimits.freeMaxPins, snippets: 0)
        #expect(pinsFull.fraction == 1)
        #expect(LibraryProMeter(boards: 0, pins: 0, snippets: snippets * 2).fraction == 1)
        #expect(
            LibraryProMeter(boards: 1, pins: 2, snippets: 3).ceilings.map(\.limit) == [
                boards, PinLimits.freeMaxPins, snippets
            ])
    }

    @Test("Pressure escalates on whichever ceiling is closest, pins included")
    func pressure() {
        let boards = PinLimits.freeMaxPinboards
        let pins = PinLimits.freeMaxPins
        #expect(LibraryProMeter(boards: 0, pins: 0, snippets: 0).pressure == .comfortable)
        #expect(LibraryProMeter(boards: boards - 1, pins: 0, snippets: 0).pressure == .almostFull)
        #expect(LibraryProMeter(boards: 0, pins: pins - 1, snippets: 0).pressure == .almostFull)
        #expect(LibraryProMeter(boards: 0, pins: pins, snippets: 0).pressure == .reached)
        #expect(
            LibraryProMeter(boards: 0, pins: 0, snippets: SnippetLimits.freeMaxSnippets)
                .pressure == .reached)
    }

    /// Typed up front: an inferred array of mixed tuple literals times out older compilers.
    static let ages: [(Double, CompactAge)] = [
        (30, .now), (7 * 60, .minutes(7)), (3 * 3600, .hours(3)), (86_400, .days(1)),
        (29 * 86_400, .days(29))
    ]

    @Test("Age reads now, minutes, hours, days, then the date", arguments: ages)
    func age(seconds: Double, expected: CompactAge) {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        #expect(CompactAge(since: now.addingTimeInterval(-seconds), now: now) == expected)
    }

    @Test("A month or more shows the date; a clock skew in the future reads now")
    func ageEdges() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let old = now.addingTimeInterval(-31 * 86_400)
        #expect(CompactAge(since: old, now: now) == .date(old))
        #expect(CompactAge(since: now.addingTimeInterval(120), now: now) == .now)
    }
}
