import Foundation

/// Talks to the Lemon Squeezy License API — the authority for direct-download
/// entitlements. Gancho activates a purchased key, re-validates it on a
/// schedule, and can release the slot again; it never issues an entitlement of
/// its own, so no signing key has to ship inside the app.
///
/// The network egress is injected (`Transport`) instead of performed here, so
/// this type stays pure and testable and the single real network call is wired
/// at the app's composition root — GanchoKit itself never reaches the network.
/// Only the license key and instance id ever leave the device: no clipboard
/// content, and nothing that identifies what the user copied.
public struct LemonSqueezyValidator: Sendable {
    public enum Result: Sendable, Equatable {
        case confirmed(instanceID: String)
        case rejected(reason: String)
        case unreachable(reason: String)
    }

    /// Performs the HTTP round-trip. The app passes a URLSession-backed closure;
    /// tests pass a canned one.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let endpoint: URL
    private let transport: Transport

    public init(
        endpoint: URL = URL(string: "https://api.lemonsqueezy.com/v1/licenses")!,
        transport: @escaping Transport
    ) {
        self.endpoint = endpoint
        self.transport = transport
    }

    public func activate(licenseKey: String, instanceName: String) async -> Result {
        await post(
            path: "activate",
            fields: ["license_key": licenseKey, "instance_name": instanceName]
        ) { payload in
            guard payload.activated == true, let id = payload.instance?.id else { return nil }
            return id
        }
    }

    /// Re-confirms a license Gancho already activated. Lemon Squeezy reports a
    /// refunded, expired, or disabled license here, which is how revocation
    /// reaches an install that is already running.
    public func validate(licenseKey: String, instanceID: String) async -> Result {
        await post(
            path: "validate",
            fields: ["license_key": licenseKey, "instance_id": instanceID]
        ) { payload in
            payload.valid == true ? instanceID : nil
        }
    }

    /// Releases this install's activation slot so the license can be moved to
    /// another Mac. Lemon Squeezy enforces the per-license activation limit.
    public func deactivate(licenseKey: String, instanceID: String) async -> Result {
        await post(
            path: "deactivate",
            fields: ["license_key": licenseKey, "instance_id": instanceID]
        ) { payload in
            payload.deactivated == true ? instanceID : nil
        }
    }

    /// One form-encoded POST plus the shared failure semantics: a transport
    /// error or an unreadable body is `unreachable` (retry later, keep any
    /// existing entitlement within grace), while a well-formed negative answer
    /// is `rejected` (Lemon Squeezy has spoken — drop Pro).
    private func post(
        path: String, fields: [String: String],
        identifier: (Response) -> String?
    ) async -> Result {
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            fields
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(Self.formEncoded($0.value))" }
                .joined(separator: "&")
                .utf8)

        let data: Data
        do {
            (data, _) = try await transport(request)
        } catch {
            return .unreachable(reason: error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Response.self, from: data) else {
            return .unreachable(reason: "Unexpected Lemon Squeezy response")
        }
        if let id = identifier(payload) { return .confirmed(instanceID: id) }
        return .rejected(reason: payload.error ?? "License key is not active")
    }

    private static func formEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }

    /// Lemon Squeezy answers all three endpoints with the same envelope; each
    /// one only sets the flag that concerns it, so every flag is optional —
    /// synthesized `Decodable` treats a missing key as an error rather than
    /// falling back to a default, which would turn every well-formed answer
    /// into `unreachable`. The instance id is what a later validate or
    /// deactivate must quote, so activation reads it from `instance`.
    private struct Response: Decodable {
        let activated: Bool?
        let valid: Bool?
        let deactivated: Bool?
        let error: String?
        let instance: ResponseInstance?
    }

    /// A sibling rather than a nested type: the lint budget allows one level of
    /// nesting, and `Response` already spends it.
    private struct ResponseInstance: Decodable {
        let id: String
    }
}

/// Turns a Lemon Squeezy license key into a stored activation, and keeps that
/// activation honest afterwards.
///
/// There is no signing key: Lemon Squeezy issues the entitlement and Gancho
/// records it. That is the whole point of this design — a distributed build
/// carries nothing an attacker could extract to mint entitlements with.
public struct LicenseActivationService: Sendable {
    public enum Outcome: Sendable, Equatable {
        case activated(LicenseActivationRecord)
        case rejected(reason: String)
        case unreachable(reason: String)
    }

    /// What a re-check concluded about an activation Gancho already holds.
    public enum Refresh: Sendable, Equatable {
        /// Still valid; the record carries a fresh `lastValidatedAt`.
        case confirmed(LicenseActivationRecord)
        /// Lemon Squeezy says this license is no longer entitled — refunded,
        /// expired, or deactivated elsewhere. Drop Pro and forget the record.
        case revoked(reason: String)
        /// Could not reach Lemon Squeezy. The caller keeps the existing record
        /// and lets `LicenseEntitlementPolicy` decide whether grace still holds.
        case unreachable(reason: String)
    }

    private let validator: LemonSqueezyValidator
    private let now: @Sendable () -> Date

    public init(
        validator: LemonSqueezyValidator,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.validator = validator
        self.now = now
    }

    public func activate(licenseKey: String, instanceName: String) async -> Outcome {
        switch await validator.activate(licenseKey: licenseKey, instanceName: instanceName) {
        case .confirmed(let instanceID):
            let stamp = now()
            return .activated(
                LicenseActivationRecord(
                    licenseKey: licenseKey, instanceID: instanceID,
                    activatedAt: stamp, lastValidatedAt: stamp))
        case .rejected(let reason):
            return .rejected(reason: reason)
        case .unreachable(let reason):
            return .unreachable(reason: reason)
        }
    }

    /// Asks Lemon Squeezy whether a stored activation is still entitled.
    ///
    /// A rejection is authoritative and revokes; an unreachable network is not,
    /// so it never takes Pro away on its own.
    public func refresh(_ record: LicenseActivationRecord) async -> Refresh {
        switch await validator.validate(
            licenseKey: record.licenseKey, instanceID: record.instanceID)
        {
        case .confirmed:
            var refreshed = record
            refreshed.lastValidatedAt = now()
            return .confirmed(refreshed)
        case .rejected(let reason):
            return .revoked(reason: reason)
        case .unreachable(let reason):
            return .unreachable(reason: reason)
        }
    }

    /// Releases this install's slot so the license can move to another Mac.
    public func deactivate(_ record: LicenseActivationRecord) async -> Refresh {
        switch await validator.deactivate(
            licenseKey: record.licenseKey, instanceID: record.instanceID)
        {
        case .confirmed: .revoked(reason: "Deactivated on this Mac")
        case .rejected(let reason): .revoked(reason: reason)
        case .unreachable(let reason): .unreachable(reason: reason)
        }
    }
}

/// The Lemon Squeezy hosted checkout where a buyer purchases a direct-download
/// license. The paywall opens this; the buyer then activates the emailed key.
public enum LemonSqueezyStore {
    public static let checkoutURL = URL(
        string: "https://johnny4young.lemonsqueezy.com/checkout/buy/"
            + "be41fa28-055d-4803-893d-9ddada3cc89d")!
}
