import Foundation
import GanchoKit
import Testing

@testable import GanchoDesign

@Suite("Countdown — the ring's fraction, last minute and clock")
struct TimeRingTests {
    static let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    static let ten = Countdown(start: start, deadline: start.addingTimeInterval(600))

    private func at(_ elapsed: TimeInterval) -> Date { Self.start.addingTimeInterval(elapsed) }

    @Test("The fraction is the share of the span left, clamped to 0...1")
    func fraction() {
        #expect(Self.ten.fraction(at: at(0)) == 1)
        #expect(Self.ten.fraction(at: at(150)) == 0.75)
        #expect(Self.ten.fraction(at: at(600)) == 0)
        #expect(Self.ten.fraction(at: at(900)) == 0, "past the deadline")
        #expect(Self.ten.fraction(at: at(-60)) == 1, "a clock set back")
        #expect(Countdown(start: Self.start, deadline: Self.start).fraction(at: at(0)) == 0)
    }

    @Test("Urgent only inside the last minute, and never once it has run out")
    func urgent() {
        #expect(!Self.ten.isUrgent(at: at(0)))
        #expect(!Self.ten.isUrgent(at: at(540)), "exactly 1:00 is not yet urgent")
        #expect(Self.ten.isUrgent(at: at(541)))
        #expect(Self.ten.isUrgent(at: at(599.5)))
        #expect(!Self.ten.isUrgent(at: at(600)))
        #expect(!Self.ten.isRunning(at: at(600)))
        #expect(Self.ten.isRunning(at: at(599.5)))
    }

    @Test("The clock reads m:ss, rounds up, and grows an hour field")
    func clock() {
        #expect(Self.ten.clock(at: at(0)) == "10:00")
        #expect(Self.ten.clock(at: at(19)) == "9:41")
        #expect(Self.ten.clock(at: at(552)) == "0:48")
        #expect(Self.ten.clock(at: at(599.2)) == "0:01", "not 0:00 while time is left")
        #expect(Self.ten.clock(at: at(700)) == "0:00")
        let long = Countdown(start: Self.start, deadline: Self.start.addingTimeInterval(3845))
        #expect(long.clock(at: at(0)) == "1:04:05")
    }

    @Test("Only a protected clip with an expiry has a lifetime; the setting can shorten it")
    func clipLifetime() {
        let expiry = Self.start.addingTimeInterval(600)
        let secret = ClipItem(
            createdAt: Self.start, kind: .secret, contentHash: "s", isSensitive: true,
            expiresAt: expiry)
        #expect(Countdown(item: secret) == Self.ten)
        #expect(Countdown(item: secret, lifetime: 3600) == Self.ten, "the stored expiry is earlier")
        #expect(
            Countdown(item: secret, lifetime: 120)?.deadline == Self.start.addingTimeInterval(120))

        let plain = ClipItem(createdAt: Self.start, contentHash: "p", expiresAt: expiry)
        #expect(Countdown(item: plain) == nil)
        #expect(Countdown(item: ClipItem(kind: .secret, contentHash: "n")) == nil, "no expiry")
    }
}
