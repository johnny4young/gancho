import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Search tokens — key:value words become filters")
struct SearchTokensTests {
    static let board = UUID()
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    static let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC

    let parser = SearchTokenParser(
        candidates: { key in
            switch key {
            case .app:
                [
                    SearchTokenCandidate(title: "Xcode", value: "com.apple.dt.Xcode"),
                    SearchTokenCandidate(title: "Safari", value: "com.apple.Safari")
                ]
            case .board: [SearchTokenCandidate(title: "Work", value: board.uuidString)]
            case .device: [SearchTokenCandidate(title: "MacBook Pro", value: "MacBook Pro")]
            default: []
            }
        }, now: now, calendar: calendar)

    @Test("Each key resolves its value to the filter it sets")
    func resolvesEveryKey() {
        #expect(parser.filter(for: "app:xcode") == .app(bundleID: "com.apple.dt.Xcode"))
        #expect(parser.filter(for: "type:code") == .type(.code))
        #expect(parser.filter(for: "board:work") == .board(Self.board))
        #expect(parser.filter(for: "device:macbook") == .device("MacBook Pro"))
        #expect(parser.filter(for: "TYPE:Links") == .type(.links), "keys and values ignore case")
    }

    @Test("before: takes today, yesterday, a day count or an ISO date")
    func beforeDates() {
        let today = Self.calendar.startOfDay(for: Self.now)
        #expect(parser.filter(for: "before:today") == .before(today))
        #expect(
            parser.filter(for: "before:yesterday") == .before(today.addingTimeInterval(-86_400)))
        #expect(parser.filter(for: "before:7d") == .before(today.addingTimeInterval(-7 * 86_400)))
        let october = Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        #expect(parser.filter(for: "before:2026-10-01") == .before(october))
    }

    @Test("Unknown keys, empty values, invalid dates and unmatched values stay text")
    func staysText() {
        #expect(parser.filter(for: "tag:work") == nil)
        #expect(parser.filter(for: "app:") == nil)
        #expect(parser.filter(for: "before:2026-13-45") == nil)
        #expect(parser.filter(for: "before:0d") == nil)
        #expect(parser.filter(for: "app:Figma") == nil)
        #expect(parser.filter(for: "type:music") == nil)
        #expect(parser.filter(for: "greeting") == nil)
        #expect(parser.filter(for: "#tag") == nil, "#tag is not a filter")
    }

    @Test("Tab completes a key prefix, then a value for that key")
    func completions() {
        #expect(parser.completions(for: "greeting ty") == [.key(.type)])
        #expect(parser.completions(for: "b") == [.key(.board), .key(.before)])
        #expect(
            parser.completions(for: "x app:sa")
                == [.value(.app, SearchTokenCandidate(title: "Safari", value: "com.apple.Safari"))])
        #expect(parser.completions(for: "type:").count == 5, "an empty value lists every type")
        #expect(parser.completions(for: "greeting ").isEmpty, "a finished word completes nothing")
        #expect(parser.completions(for: "nope:x").isEmpty)
    }

    @Test("An exact title outranks a longer one that shares its prefix")
    func exactFirst() {
        let parser = SearchTokenParser(candidates: { _ in
            [
                SearchTokenCandidate(title: "Notes Pro", value: "pro"),
                SearchTokenCandidate(title: "Notes", value: "notes")
            ]
        })
        #expect(parser.filter(for: "app:notes") == .app(bundleID: "notes"))
    }
}
