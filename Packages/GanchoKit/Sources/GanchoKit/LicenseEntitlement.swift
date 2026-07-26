import Foundation

/// What Lemon Squeezy returned when this install activated a license, plus when
/// Gancho last re-confirmed it.
///
/// Lemon Squeezy is the authority. Gancho never mints an entitlement — it
/// records the one Lemon Squeezy issued and re-confirms it, so no signing key
/// has to exist inside a distributed build. `instanceID` is what Lemon Squeezy
/// counts against the license's activation limit and what a deactivation
/// releases, so it identifies this install for the license's whole lifetime.
public struct LicenseActivationRecord: Codable, Equatable, Sendable {
    public let licenseKey: String
    public let instanceID: String
    public let activatedAt: Date
    /// The last time Lemon Squeezy confirmed the license was still valid.
    /// Offline grace is measured from here, not from `activatedAt`.
    public var lastValidatedAt: Date

    public init(
        licenseKey: String, instanceID: String, activatedAt: Date, lastValidatedAt: Date
    ) {
        self.licenseKey = licenseKey
        self.instanceID = instanceID
        self.activatedAt = activatedAt
        self.lastValidatedAt = lastValidatedAt
    }
}

/// What a stored activation entitles this install to right now.
public enum LicenseEntitlement: Sendable, Equatable {
    /// Confirmed by Lemon Squeezy, or within the offline grace window.
    case pro
    /// A real activation exists, but Lemon Squeezy has been unreachable for
    /// longer than the grace window, so Pro can no longer be assumed. Kept
    /// distinct from `none` so the paywall can say "reconnect to keep Pro"
    /// rather than "buy Gancho".
    case lapsed
    /// No activation on this install.
    case none
}

/// Decides, offline, what a stored activation is worth — and when to ask Lemon
/// Squeezy again.
///
/// The two windows are deliberately different. Re-validation is attempted often
/// so a revoked or refunded license stops working promptly. Grace is much
/// longer so an ordinary offline stretch — a flight, a laptop that lives on a
/// train — never takes Pro away from someone who paid.
///
/// Without a signing key there is no cryptographic barrier against a user
/// editing their own Keychain record to postpone the next check. That is
/// accepted: the exposure is one install extending its own Pro until the next
/// successful validation, whereas an embedded private key would let a single
/// extracted build mint entitlements for everyone, permanently.
public enum LicenseEntitlementPolicy: Sendable {
    /// How often Gancho asks Lemon Squeezy to confirm a license it already holds.
    public static let revalidationInterval: TimeInterval = 7 * 24 * 60 * 60
    /// How long a confirmed license keeps working with no reachable network.
    public static let offlineGrace: TimeInterval = 30 * 24 * 60 * 60

    public static func entitlement(
        for record: LicenseActivationRecord?, now: Date,
        grace: TimeInterval = offlineGrace
    ) -> LicenseEntitlement {
        guard let record else { return .none }
        // A clock pushed backwards must not extend grace forever, and a record
        // validated "in the future" is still a record we confirmed.
        guard now.timeIntervalSince(record.lastValidatedAt) <= grace else { return .lapsed }
        return .pro
    }

    /// True when the record is old enough that Gancho should try Lemon Squeezy
    /// again. A lapsed record always wants revalidation: reconnecting is the
    /// only way back to Pro.
    ///
    /// A clock BEHIND the stamp is due immediately. Otherwise moving the clock
    /// back would postpone revalidation indefinitely, and a refunded or revoked
    /// license would keep working for as long as the clock stayed wrong.
    public static func needsRevalidation(
        _ record: LicenseActivationRecord, now: Date,
        interval: TimeInterval = revalidationInterval
    ) -> Bool {
        let elapsed = now.timeIntervalSince(record.lastValidatedAt)
        return elapsed < 0 || elapsed >= interval
    }
}

/// Deterministic coding for the stored activation record: sorted keys and
/// ISO-8601 dates, so a record written today reads back identically tomorrow.
/// ISO-8601 truncates sub-seconds — callers comparing a re-read record must
/// compare identity, not whole-value equality.
extension JSONEncoder {
    static var license: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var license: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
