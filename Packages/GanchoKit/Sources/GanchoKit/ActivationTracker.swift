import Foundation

/// Closed, content-free milestones that describe whether Gancho delivered its
/// core value. No clip, query, application, board, or snippet identity is stored.
public enum ActivationMilestone: String, Sendable, Equatable, CaseIterable {
    case onboardingCompleted = "onboarding_completed"
    case firstCapture = "first_capture"
    case firstSearch = "first_search"
    case firstSuccessfulReuse = "first_successful_reuse"
    case firstBoardCreated = "first_board_created"
    case firstSnippetCreated = "first_snippet_created"
}

/// Broad reuse families only. The associated clip and destination never cross
/// the telemetry boundary.
public enum SuccessfulReuseMethod: String, Sendable, Equatable, CaseIterable {
    case paste
    case transform
    case drag
    case snippet
    case smartPaste = "smart_paste"
    case copy
}

/// Coarse elapsed-time buckets used for first-value and onboarding analysis.
public enum ActivationTimeBucket: String, Sendable, Equatable, CaseIterable {
    case underMinute = "under_minute"
    case underFiveMinutes = "under_five_minutes"
    case underHour = "under_hour"
    case sameDay = "same_day"
    case later
    case unknown

    public init(elapsed: TimeInterval?) {
        guard let elapsed else {
            self = .unknown
            return
        }
        switch max(0, elapsed) {
        case ..<60: self = .underMinute
        case ..<300: self = .underFiveMinutes
        case ..<3_600: self = .underHour
        case ..<86_400: self = .sameDay
        default: self = .later
        }
    }
}

/// Aggregate state sent once, and only after the user explicitly opts in. It
/// lets a pre-consent first value be counted without replaying individual
/// actions that happened before consent.
public struct ActivationSnapshot: Sendable, Equatable {
    public let completedMilestones: Set<ActivationMilestone>
    public let timeToFirstReuse: ActivationTimeBucket
    public let onboardingDuration: ActivationTimeBucket

    public init(
        completedMilestones: Set<ActivationMilestone>,
        timeToFirstReuse: ActivationTimeBucket,
        onboardingDuration: ActivationTimeBucket
    ) {
        self.completedMilestones = completedMilestones
        self.timeToFirstReuse = timeToFirstReuse
        self.onboardingDuration = onboardingDuration
    }

    var encodedParameters: [String: String] {
        var parameters = Dictionary(
            uniqueKeysWithValues: ActivationMilestone.allCases.map {
                ($0.rawValue, completedMilestones.contains($0) ? "complete" : "pending")
            })
        parameters["time_to_first_reuse"] = timeToFirstReuse.rawValue
        parameters["onboarding_duration"] = onboardingDuration.rawValue
        return parameters
    }
}

/// Receipt returned only for the first occurrence of a milestone.
public struct ActivationMilestoneReceipt: Sendable, Equatable {
    public let milestone: ActivationMilestone
    public let elapsedBucket: ActivationTimeBucket
}

/// Minimal local activation receipt. Exact dates remain in this app's defaults
/// only; telemetry receives closed buckets after consent. An explicit refusal
/// calls `reset()`, removing every receipt and the local start date.
public final class ActivationTracker: @unchecked Sendable {
    private static let keyPrefix = "telemetry-activation."
    private static let startedAtKey = keyPrefix + "started-at"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func start(at date: Date = .now) {
        lock.withLock {
            guard defaults.object(forKey: Self.startedAtKey) == nil else { return }
            defaults.set(date, forKey: Self.startedAtKey)
        }
    }

    @discardableResult
    public func record(
        _ milestone: ActivationMilestone, at date: Date = .now
    ) -> ActivationMilestoneReceipt? {
        lock.withLock {
            let key = Self.key(for: milestone)
            guard defaults.object(forKey: key) == nil else { return nil }
            let startedAt = defaults.object(forKey: Self.startedAtKey) as? Date
            if startedAt == nil { defaults.set(date, forKey: Self.startedAtKey) }
            defaults.set(date, forKey: key)
            return ActivationMilestoneReceipt(
                milestone: milestone,
                elapsedBucket: ActivationTimeBucket(
                    elapsed: startedAt.map { date.timeIntervalSince($0) } ?? 0))
        }
    }

    public func snapshot() -> ActivationSnapshot {
        lock.withLock {
            let milestones = Set(
                ActivationMilestone.allCases.filter {
                    defaults.object(forKey: Self.key(for: $0)) != nil
                })
            let startedAt = defaults.object(forKey: Self.startedAtKey) as? Date
            let firstReuse =
                defaults.object(
                    forKey: Self.key(for: .firstSuccessfulReuse)) as? Date
            let onboardingCompleted =
                defaults.object(
                    forKey: Self.key(for: .onboardingCompleted)) as? Date
            return ActivationSnapshot(
                completedMilestones: milestones,
                timeToFirstReuse: ActivationTimeBucket(
                    elapsed: startedAt.flatMap { start in
                        firstReuse.map { $0.timeIntervalSince(start) }
                    }),
                onboardingDuration: ActivationTimeBucket(
                    elapsed: startedAt.flatMap { start in
                        onboardingCompleted.map { $0.timeIntervalSince(start) }
                    }))
        }
    }

    public func reset() {
        lock.withLock {
            defaults.removeObject(forKey: Self.startedAtKey)
            for milestone in ActivationMilestone.allCases {
                defaults.removeObject(forKey: Self.key(for: milestone))
            }
        }
    }

    private static func key(for milestone: ActivationMilestone) -> String {
        keyPrefix + milestone.rawValue
    }
}
