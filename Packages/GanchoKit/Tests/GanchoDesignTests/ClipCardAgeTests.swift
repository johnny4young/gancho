import Foundation
import Testing

@testable import GanchoDesign

@Suite("ClipCard — the phone row's short age")
struct ClipCardAgeTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let english = Locale(identifier: "en_US")

    private func age(_ seconds: TimeInterval, _ locale: Locale? = nil) -> String {
        ClipCard.shortAge(
            since: now.addingTimeInterval(-seconds), now: now, locale: locale ?? english)
    }

    @Test("Abbreviated units in the largest whole unit")
    func units() {
        #expect(age(6 * 60) == "6 min")
        #expect(age(90 * 60) == "1 hr")
        #expect(age(2 * 86_400) == "2 days")
        #expect(age(15 * 86_400) == "2 wks")
    }

    @Test("Never under a minute, also for a clock that runs behind")
    func floor() {
        #expect(age(5) == "1 min")
        #expect(age(-30) == "1 min")
    }

    @Test("Spanish uses its own abbreviations")
    func spanish() {
        #expect(age(3_600, Locale(identifier: "es_MX")) == "1 h")
    }
}
