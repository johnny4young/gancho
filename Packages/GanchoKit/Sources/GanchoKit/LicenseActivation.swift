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

    /// Public identifiers of the live Gancho Pro product — the same identity
    /// the hosted checkout embeds. A merely-valid Lemon Squeezy key is not
    /// authorization: the public License API accepts keys from every store,
    /// so a granting answer must also name this store and product, and must
    /// not be a test-mode key. Identifiers only, never a secret.
    static let expectedStoreID = 408_765
    static let expectedProductID = 1_178_223

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
            operation: .activate,
            fields: ["license_key": licenseKey, "instance_name": instanceName]
        ) { payload in
            guard payload.activated == true, let id = payload.instance?.id else {
                return Self.negative(payload, flag: payload.activated)
            }
            // An activation grants a brand-new entitlement, so it fails
            // closed: the answer must name the live Gancho product. A key
            // from another store, a test-mode key, or an answer with no
            // identity at all activates nothing.
            return Self.identity(payload) == .trusted
                ? .confirmed(id)
                : .denied(Self.foreignKeyReason)
        }
    }

    /// Re-confirms a license Gancho already activated. Lemon Squeezy reports a
    /// refunded, expired, or disabled license here, which is how revocation
    /// reaches an install that is already running.
    public func validate(licenseKey: String, instanceID: String) async -> Result {
        await post(
            operation: .validate,
            fields: ["license_key": licenseKey, "instance_id": instanceID]
        ) { payload in
            guard payload.valid == true else {
                return Self.negative(payload, flag: payload.valid)
            }
            // Revalidation guards an entitlement the user already holds, so
            // only an identity Lemon Squeezy actually stated may revoke it: a
            // foreign store or a test-mode key is an explicit answer, while a
            // valid-shaped answer that names no store at all is unrecognized
            // and keeps the grace window — a response-shape change at their
            // end must never read as a mass revocation.
            switch Self.identity(payload) {
            case .trusted: return .confirmed(instanceID)
            case .foreign: return .denied(Self.foreignKeyReason)
            case .absent: return .unrecognized
            }
        }
    }

    /// Releases this install's activation slot so the license can be moved to
    /// another Mac. Lemon Squeezy enforces the per-license activation limit.
    /// Deliberately not identity-pinned: releasing a slot grants nothing, and
    /// the caller drops the local record on a confirmation and on a denial
    /// alike, so a pin here could not keep or mint an entitlement either way.
    public func deactivate(licenseKey: String, instanceID: String) async -> Result {
        await post(
            operation: .deactivate,
            fields: ["license_key": licenseKey, "instance_id": instanceID]
        ) { payload in
            payload.deactivated == true
                ? .confirmed(instanceID) : Self.negative(payload, flag: payload.deactivated)
        }
    }

    /// How an endpoint reads its own answer. Three-way on purpose: only an
    /// explicit negative may revoke, so a body Gancho does not recognize is
    /// never mistaken for Lemon Squeezy saying no. A denial may carry its own
    /// reason; without one, the server's error (or a generic line) is used.
    private enum Verdict {
        case confirmed(String)
        case denied(String?)
        case unrecognized
    }

    /// HTTP failures have endpoint-specific authority. Activation has no
    /// entitlement to preserve, and Lemon Squeezy documents a small set of
    /// client-error statuses for an invalid activation request. Revalidation
    /// and deactivation already have local state, so only a successful HTTP
    /// exchange may change it.
    private enum Operation: String {
        case activate
        case validate
        case deactivate

        var acceptsHTTPRejection: Bool { self == .activate }
    }

    /// An explicit `false` flag, or an error the server supplied, is Lemon
    /// Squeezy denying the request. Anything else — a missing flag, a partial
    /// body, a future response shape — is unrecognized and must NOT revoke: a
    /// change at their end would otherwise drop Pro for every paying user at
    /// once, and the whole point of the grace window is to survive exactly that.
    private static func negative(_ payload: Response, flag: Bool?) -> Verdict {
        flag == false || payload.error != nil ? .denied(nil) : .unrecognized
    }

    /// The user-facing reason when a key is valid somewhere, just not here.
    private static let foreignKeyReason = "That license key is not a Gancho Pro license"

    /// Whose product an answer says the key belongs to. `absent` is distinct
    /// from `foreign` on purpose: naming the wrong store (or `test_mode`) is
    /// Lemon Squeezy answering, while naming no store at all — both pinned
    /// fields missing — is a shape this code does not recognize. A partial
    /// identity counts as absent so a renamed field can never mass-revoke.
    private enum Identity {
        case trusted
        case foreign
        case absent
    }

    private static func identity(_ payload: Response) -> Identity {
        if payload.licenseKey?.testMode == true { return .foreign }
        guard let store = payload.meta?.storeId, let product = payload.meta?.productId else {
            return .absent
        }
        return store == expectedStoreID && product == expectedProductID ? .trusted : .foreign
    }

    /// One form-encoded POST plus the shared failure semantics. Transport
    /// failures, non-HTTP responses, and service/auth/rate-limit HTTP failures
    /// are `unreachable` (retry later and preserve existing grace). Only a 2xx
    /// endpoint verdict — or a documented activation client error carrying a
    /// readable reason — is authoritative enough to be `rejected`.
    private func post(
        operation: Operation, fields: [String: String],
        verdict: (Response) -> Verdict
    ) async -> Result {
        var request = URLRequest(url: endpoint.appendingPathComponent(operation.rawValue))
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
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            return .unreachable(reason: Self.serviceUnavailableReason)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let httpResponse = response as? HTTPURLResponse else {
            return .unreachable(reason: Self.serviceUnavailableReason)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            guard
                operation.acceptsHTTPRejection,
                Self.activationRejectionStatuses.contains(httpResponse.statusCode),
                let payload = try? decoder.decode(Response.self, from: data),
                let reason = payload.error?.trimmingCharacters(in: .whitespacesAndNewlines),
                !reason.isEmpty
            else {
                return .unreachable(reason: Self.serviceUnavailableReason)
            }
            return .rejected(reason: reason)
        }

        guard let payload = try? decoder.decode(Response.self, from: data) else {
            return .unreachable(reason: "Unexpected Lemon Squeezy response")
        }
        switch verdict(payload) {
        case .confirmed(let id): return .confirmed(instanceID: id)
        case .denied(let reason):
            return .rejected(reason: reason ?? payload.error ?? "License key is not active")
        case .unrecognized: return .unreachable(reason: "Unexpected Lemon Squeezy response")
        }
    }

    private static let activationRejectionStatuses: Set<Int> = [400, 404, 422]
    private static let serviceUnavailableReason = "Lemon Squeezy is temporarily unavailable"

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
        let licenseKey: ResponseLicenseKey?
        let meta: ResponseMeta?
    }

    /// A sibling rather than a nested type: the lint budget allows one level of
    /// nesting, and `Response` already spends it.
    private struct ResponseInstance: Decodable {
        let id: String
    }

    /// The identity slice of the `license_key` object; everything else in it
    /// is unused. (`test_mode` arrives as `testMode` via snake-case decoding.)
    private struct ResponseLicenseKey: Decodable {
        let testMode: Bool?
    }

    /// Who issued the key — what the pinned store/product check reads.
    /// Property names match the decoder's snake-case conversion (`store_id`
    /// becomes `storeId`), which is why the second letter is lowercase.
    private struct ResponseMeta: Decodable {
        let storeId: Int?
        let productId: Int?
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
