import GanchoKit
import SwiftUI

/// A span of time that runs out: a secret's lifetime, a timed mode.
public struct Countdown: Equatable, Sendable {
    /// Below this the ring reads as urgent.
    public static let urgentWindow: TimeInterval = 60

    public let start: Date
    public let deadline: Date

    public init(start: Date, deadline: Date) {
        self.start = start
        self.deadline = deadline
    }

    /// A protected clip's lifetime; nil when it has no expiry. `lifetime` is
    /// the current setting: retention purges by capture time once it is
    /// shortened, so the earlier of the two is the real deadline.
    public init?(item: ClipItem, lifetime: TimeInterval? = nil) {
        guard ClipSafePresentation.requiresMasking(item), let expiresAt = item.expiresAt
        else { return nil }
        start = item.createdAt
        deadline =
            lifetime.map { min(expiresAt, item.createdAt.addingTimeInterval($0)) }
            ?? expiresAt
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }

    public func isRunning(at now: Date) -> Bool {
        remaining(at: now) > 0
    }

    /// Remaining share of the whole span, 0...1.
    public func fraction(at now: Date) -> Double {
        let total = deadline.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, remaining(at: now) / total)
    }

    /// The last minute, while time is still left.
    public func isUrgent(at now: Date) -> Bool {
        let left = remaining(at: now)
        return left > 0 && left < Self.urgentWindow
    }

    /// "9:41", or "1:04:05" from an hour up. Rounded up, so it reaches 0:00
    /// only when nothing is left.
    public func clock(at now: Date) -> String {
        let seconds = Int(remaining(at: now).rounded(.up))
        let (hours, minutes, rest) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        let tail = String(format: "%02d", rest)
        return hours > 0
            ? "\(hours):\(String(format: "%02d", minutes)):\(tail)" : "\(minutes):\(tail)"
    }
}

/// Time left as a ring that empties: hairline track, ink progress, red only in
/// the last minute. Ticks once a second; under Reduce Motion it steps.
public struct TimeRing<Center: View>: View {
    let countdown: Countdown
    let lineWidth: CGFloat
    let center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ countdown: Countdown, lineWidth: CGFloat = 2,
        @ViewBuilder center: () -> Center = { EmptyView() }
    ) {
        self.countdown = countdown
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        // Anchored to the deadline, so the ring and a clock beside it tick together.
        TimelineView(.periodic(from: countdown.deadline, by: 1)) { context in
            let fraction = countdown.fraction(at: context.date)
            ZStack {
                Circle()
                    .strokeBorder(GanchoTokens.Palette.hairline, lineWidth: lineWidth)
                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: 0, to: fraction)
                    .stroke(
                        countdown.isUrgent(at: context.date)
                            ? GanchoTokens.Palette.danger : GanchoTokens.Palette.ink,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(GanchoMotion.tick(reduceMotion: reduceMotion), value: fraction)
                center
            }
            .accessibilityElement(children: .ignore)
            .accessibilityValue(Text("\(countdown.clock(at: context.date)) left"))
        }
    }
}
