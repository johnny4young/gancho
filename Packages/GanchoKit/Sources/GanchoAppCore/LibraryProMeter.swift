import Foundation
import GanchoKit

/// The Library's Pro card on Free: every ceiling (boards, pins, snippets) read
/// from the code constants, filled to the fullest one, and warning as the
/// fullest gets close.
public struct LibraryProMeter: Equatable, Sendable {
    public struct Ceiling: Equatable, Sendable, Identifiable {
        public let kind: LibraryProCeiling
        public let used: Int
        public let limit: Int
        public var id: LibraryProCeiling { kind }
        public var left: Int { limit - used }
    }

    public let ceilings: [Ceiling]

    public init(boards: Int, pins: Int, snippets: Int) {
        ceilings = [
            Ceiling(kind: .boards, used: boards, limit: PinLimits.freeMaxPinboards),
            Ceiling(kind: .pins, used: pins, limit: PinLimits.freeMaxPins),
            Ceiling(kind: .snippets, used: snippets, limit: SnippetLimits.freeMaxSnippets)
        ]
    }

    /// The fullest ceiling's share, 0…1.
    public var fraction: Double {
        let shares = ceilings.map { Double($0.used) / Double(max($0.limit, 1)) }
        return min(max(shares.max() ?? 0, 0), 1)
    }

    public var pressure: FreeTierLimits.Pressure {
        FreeTierLimits.pressure(slotsLeft: ceilings.map(\.left).min() ?? 0)
    }
}

/// The Free limits the Library's Pro card counts.
public enum LibraryProCeiling: String, CaseIterable, Sendable { case boards, pins, snippets }

/// How long ago a clip was copied, as the Library card's meta line says it.
public enum CompactAge: Equatable, Sendable {
    case now
    case minutes(Int)
    case hours(Int)
    case days(Int)
    /// Past a month the date reads better than a count.
    case date(Date)

    public init(since date: Date, now: Date = .now) {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: self = .now
        case ..<3600: self = .minutes(Int(seconds / 60))
        case ..<86_400: self = .hours(Int(seconds / 3600))
        case ..<(30 * 86_400): self = .days(Int(seconds / 86_400))
        default: self = .date(date)
        }
    }
}
