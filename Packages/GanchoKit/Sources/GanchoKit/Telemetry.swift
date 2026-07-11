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
    case itemCaptured(type: ClipContentKind, lengthBucket: LengthBucket)
    case itemPastedBack(ageBucket: AgeBucket)
    case itemPinned
    case itemDeleted
    case searchPerformed
    case aiActionUsed
    case syncEvent
    case freeLimitReached
    case paywallShown(trigger: PaywallGatekeeper.Trigger)
    case upgradeStarted(plan: ProProduct.Plan)
    case upgradeCompleted(plan: ProProduct.Plan)
    case settingsChanged(key: SettingKey)

    public enum SettingKey: String, Sendable, Equatable, CaseIterable {
        case appearance
        case capture
        case diagnostics
        case intelligence
        case retention
        case shortcuts
        case sync
    }

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
            ("item_captured", ["type": type.rawValue, "length_bucket": bucket.rawValue])
        case .itemPastedBack(let bucket):
            ("item_pasted_back", ["age_bucket": bucket.rawValue])
        case .itemPinned: ("item_pinned", [:])
        case .itemDeleted: ("item_deleted", [:])
        case .searchPerformed: ("search_performed", [:])
        case .aiActionUsed: ("ai_action_used", [:])
        case .syncEvent: ("sync_event", [:])
        case .freeLimitReached: ("free_limit_reached", [:])
        case .paywallShown(let trigger): ("paywall_shown", ["trigger": trigger.rawValue])
        case .upgradeStarted(let plan): ("upgrade_started", ["plan": plan.rawValue])
        case .upgradeCompleted(let plan): ("upgrade_completed", ["plan": plan.rawValue])
        case .settingsChanged(let key): ("settings_changed", ["key": key.rawValue])
        }
    }
}

/// Transport seam. Implementations receive only the closed event schema above;
/// an explicitly enabled pipeline may omit a transport for local-only counts.
public protocol TelemetrySending: Sendable {
    func send(name: String, parameters: [String: String]) async
}

/// Explicit consent for optional, content-free product diagnostics.
///
/// An absent preference is deliberately `notAsked`, never implicit consent.
/// The legacy opt-out Boolean only preserves an explicit refusal; an absent or
/// false legacy value cannot prove informed consent and therefore stays off.
public enum TelemetryConsent: String, Codable, Sendable, Equatable, CaseIterable {
    case notAsked
    case enabled
    case disabled

    public static let storageKey = "telemetry-consent"
    private static let legacyOptOutKey = "telemetry-opted-out"

    public static func load(from defaults: UserDefaults = .standard) -> Self {
        if let rawValue = defaults.string(forKey: storageKey),
            let consent = Self(rawValue: rawValue)
        {
            return consent
        }
        if defaults.object(forKey: legacyOptOutKey) != nil,
            defaults.bool(forKey: legacyOptOutKey)
        {
            return .disabled
        }
        return .notAsked
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.legacyOptOutKey)
    }
}

/// Pipeline: constructs a transport only after explicit consent, and destroys
/// that transport immediately when consent is withdrawn. An explicitly enabled
/// pipeline may count locally without a transport; otherwise it records nothing.
public final class TelemetryPipeline: @unchecked Sendable {
    public typealias SenderFactory = @Sendable () -> any TelemetrySending

    private let lock = NSLock()
    private let senderFactory: SenderFactory?
    private var sender: (any TelemetrySending)?
    private var isCreatingSender = false
    private var consent: TelemetryConsent
    private var localCounts: [String: Int] = [:]

    public init(
        consent: TelemetryConsent = .notAsked,
        senderFactory: SenderFactory? = nil
    ) {
        self.consent = consent
        self.senderFactory = senderFactory
        sender = consent == .enabled ? senderFactory?() : nil
    }

    public func setConsent(_ consent: TelemetryConsent) {
        guard consent == .enabled else {
            lock.withLock {
                self.consent = consent
                sender = nil
            }
            return
        }

        let shouldCreate = lock.withLock {
            self.consent = consent
            guard sender == nil, !isCreatingSender else { return false }
            isCreatingSender = true
            return true
        }
        guard shouldCreate else { return }

        // External SDK initialization must not run while holding the pipeline
        // lock. A factory may do synchronous work or call back into the app.
        let candidate = senderFactory?()
        lock.withLock {
            isCreatingSender = false
            guard self.consent == .enabled, sender == nil else { return }
            sender = candidate
        }
    }

    public func record(_ event: TelemetryEvent) {
        let (name, parameters) = event.encoded
        let sender = lock.withLock { () -> (any TelemetrySending)? in
            guard consent == .enabled else { return nil }
            localCounts[name, default: 0] += 1
            return self.sender
        }
        guard let sender else { return }
        Task { await sender.send(name: name, parameters: parameters) }
    }

    /// Privacy Center: events recorded this session, by name.
    public func counts() -> [String: Int] {
        lock.withLock { localCounts }
    }
}
