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

        // Retention's lifetime clause purges sensitive clips only.
        let token = ClipItem(createdAt: Self.start, kind: .jwt, contentHash: "j", expiresAt: expiry)
        #expect(Countdown(item: token, lifetime: 120) == Self.ten, "not sensitive: its own expiry")

        let plain = ClipItem(createdAt: Self.start, contentHash: "p", expiresAt: expiry)
        #expect(Countdown(item: plain) == nil)
        #expect(Countdown(item: ClipItem(kind: .secret, contentHash: "n")) == nil, "no expiry")
    }

    @Test("A reveal window empties over its ten seconds")
    func revealWindow() {
        let until = Self.start.addingTimeInterval(10)
        let reveal = Countdown(window: 10, endingAt: until)
        #expect(reveal.start == Self.start)
        #expect(reveal.fraction(at: at(0)) == 1)
        #expect(reveal.fraction(at: at(2.5)) == 0.75)
        #expect(reveal.fraction(at: at(10)) == 0)
    }

    @Test("A timed mode's ring runs from its start to its deadline; none without both")
    func timedMode() throws {
        let end = Self.start.addingTimeInterval(3600)
        let mode = try #require(Countdown(from: Self.start, until: end))
        #expect(mode.fraction(at: at(0)) == 1)
        #expect(mode.fraction(at: at(120)) == 58.0 / 60)
        #expect(mode.fraction(at: at(3600)) == 0)

        #expect(Countdown(from: Self.start, until: nil) == nil, "on until turned off")
        #expect(Countdown(from: nil, until: end) == nil)
        #expect(Countdown(from: end, until: Self.start) == nil, "dates out of order")
    }

    @Test("A ring redraws each second, or about once a degree on a long span")
    func tickInterval() {
        func span(_ seconds: TimeInterval) -> TimeInterval {
            Countdown(window: seconds, endingAt: Self.start).tickInterval
        }
        #expect(span(10) == 1, "a reveal")
        #expect(span(600) == 1, "a secret's lifetime")
        #expect(span(900) == 2)
        #expect(span(1800) == 5)
        #expect(span(3600) == 10, "an hour of Private Mode")
        #expect(span(86_400) == 10)
        for seconds in [10.0, 900, 1800, 3600] {
            #expect(60.0.truncatingRemainder(dividingBy: span(seconds)) == 0)
        }
    }

    @Test("Only a secret's ring turns red in its last minute; a mode's never does")
    @MainActor
    func modeRingNeverWarns() throws {
        let lastMinute = at(570)
        #expect(TimeRing(Self.ten).strokeIsUrgent(at: lastMinute))
        let mode = try #require(ModeRing(Self.ten).ring)
        #expect(!mode.strokeIsUrgent(at: lastMinute))
        #expect(ModeRing(nil).ring == nil, "no deadline: a plain ring")
    }

    @Test("A dial has 60 minute marks inside its ring, every fifth twice as long")
    func minuteTicks() throws {
        let center = CGPoint(x: 75, y: 75)
        let ticks = MinuteTicks.ticks(center: center, ringRadius: 66)
        #expect(ticks.count == 60)
        #expect(ticks.indices.filter { ticks[$0].isLong } == Array(stride(from: 0, to: 60, by: 5)))

        func length(_ tick: MinuteTicks.Tick) -> Double {
            hypot(tick.end.x - tick.start.x, tick.end.y - tick.start.y)
        }
        for tick in ticks {
            let outer = hypot(tick.start.x - center.x, tick.start.y - center.y)
            #expect(abs(outer - 57) < 0.001, "inside the ring's 64.5 pt inner edge")
            #expect(abs(length(tick) - (tick.isLong ? 5 : 2.5)) < 0.001)
        }

        // Clockwise from twelve: the first mark points down from the top, the 15th is at three.
        let top = ticks[0]
        #expect(abs(top.start.x - 75) < 0.001 && abs(top.start.y - 18) < 0.001)
        #expect(abs(top.end.y - 23) < 0.001)
        let three = ticks[15]
        #expect(abs(three.start.x - 132) < 0.001 && abs(three.start.y - 75) < 0.001)

        // The marks scale with the ring.
        let small = MinuteTicks.ticks(center: .zero, ringRadius: 33)
        #expect(abs(length(small[0]) - 2.5) < 0.001)
    }
}
