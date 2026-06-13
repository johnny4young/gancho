import Foundation

/// Telemetry that CANNOT leak content, by type design: events are a closed
/// enum and every payload field is a bucket or an enum name — there is no
/// string field a clip could travel through. The NOTES schema (decided
/// 2026-06): app_launched, item_captured{type,length_bucket},
/// item_pasted_back{age_bucket}, item_pinned, item_deleted,
/// search_performed, ai_action_used, sync_event, free_limit_reached,
/// paywall_shown{trigger}, upgrade_started/completed{plan},
/// settings_changed{key}.
public enum TelemetryEvent: Sendable, Equatable {
    case appLaunched
    case itemCaptured(type: String, lengthBucket: LengthBucket)
    case itemPastedBack(ageBucket: AgeBucket)
    case itemPinned
    case itemDeleted
    case searchPerformed
    case aiActionUsed
    case syncEvent
    case freeLimitReached
    case paywallShown(trigger: String)
    case upgradeStarted(plan: String)
    case upgradeCompleted(plan: String)
    case settingsChanged(key: String)

    public enum LengthBucket: String, Sendable, Equatable, CaseIterable {
        case tiny, short, medium, long, huge

        public init(characterCount: Int) {
            switch characterCount {
            case ..<32: self = .tiny
            case ..<256: self = .short
            case ..<2_048: self = .medium
            case ..<16_384: self = .long
            default: self = .huge
            }
        }
    }

    public enum AgeBucket: String, Sendable, Equatable, CaseIterable {
        case minutes, hours, today, thisWeek, older

        public init(age: TimeInterval) {
            switch age {
            case ..<3_600: self = .minutes
            case ..<21_600: self = .hours
            case ..<86_400: self = .today
            case ..<604_800: self = .thisWeek
            default: self = .older
            }
        }
    }

    /// Wire name + bucket parameters — the ONLY data that ever leaves.
    public var encoded: (name: String, parameters: [String: String]) {
        switch self {
        case .appLaunched: ("app_launched", [:])
        case .itemCaptured(let type, let bucket):
            ("item_captured", ["type": type, "length_bucket": bucket.rawValue])
        case .itemPastedBack(let bucket):
            ("item_pasted_back", ["age_bucket": bucket.rawValue])
        case .itemPinned: ("item_pinned", [:])
        case .itemDeleted: ("item_deleted", [:])
        case .searchPerformed: ("search_performed", [:])
        case .aiActionUsed: ("ai_action_used", [:])
        case .syncEvent: ("sync_event", [:])
        case .freeLimitReached: ("free_limit_reached", [:])
        case .paywallShown(let trigger): ("paywall_shown", ["trigger": trigger])
        case .upgradeStarted(let plan): ("upgrade_started", ["plan": plan])
        case .upgradeCompleted(let plan): ("upgrade_completed", ["plan": plan])
        case .settingsChanged(let key): ("settings_changed", ["key": key])
        }
    }
}

/// Transport seam. TelemetryDeck implements this once the app ID exists;
/// until then events queue locally and nothing leaves the device.
public protocol TelemetrySending: Sendable {
    func send(name: String, parameters: [String: String]) async
}

/// Pipeline: respects the user opt-out FIRST, then forwards encoded events.
/// With no sender configured it counts locally (Privacy Center material)
/// and sends nothing.
public final class TelemetryPipeline: @unchecked Sendable {
    private let lock = NSLock()
    private var sender: (any TelemetrySending)?
    private var optedOut: Bool
    private var localCounts: [String: Int] = [:]

    public init(sender: (any TelemetrySending)? = nil, optedOut: Bool = false) {
        self.sender = sender
        self.optedOut = optedOut
    }

    public func setOptedOut(_ value: Bool) {
        lock.withLock { optedOut = value }
    }

    public func record(_ event: TelemetryEvent) {
        let (proceed, sender) = lock.withLock { (!optedOut, self.sender) }
        guard proceed else { return }
        let (name, parameters) = event.encoded
        lock.withLock { localCounts[name, default: 0] += 1 }
        guard let sender else { return }
        Task { await sender.send(name: name, parameters: parameters) }
    }

    /// Privacy Center: events recorded this session, by name.
    public func counts() -> [String: Int] {
        lock.withLock { localCounts }
    }
}
