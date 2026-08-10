import Foundation
import Testing

@testable import GanchoKit

@Suite("Lemon Squeezy activation")
struct LicenseActivationTests {
    /// A canned transport that returns a fixed JSON body and HTTP status.
    private static func transport(
        _ json: String, status: Int = 200
    )
        -> LemonSqueezyValidator.Transport
    {
        { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(json.utf8), response)
        }
    }

    /// Live Lemon Squeezy answers always name the key's store and product;
    /// the validator pins that identity, so the happy-path fixtures carry it.
    /// Derived from the pinned constants so retuning them can't rot this file;
    /// the literal identity itself is asserted once, in
    /// `pinnedIdentityIsTheLiveProduct`.
    private static let ganchoMeta =
        #""meta":{"store_id":\#(LemonSqueezyValidator.expectedStoreID),"#
        + #""product_id":\#(LemonSqueezyValidator.expectedProductID)}"#

    private static let activatedJSON =
        #"{"activated":true,"error":null,"instance":{"id":"inst-42"},"#
        + #""license_key":{"test_mode":false},"# + ganchoMeta + "}"

    private static let validJSON =
        #"{"valid":true,"instance":{"id":"i-1"},"# + ganchoMeta + "}"

    @Test("An active license key yields the instance id Lemon Squeezy assigned")
    func activated() async {
        let validator = LemonSqueezyValidator(transport: Self.transport(Self.activatedJSON))
        let result = await validator.activate(licenseKey: "K-1", instanceName: "Mac")
        #expect(result == .confirmed(instanceID: "inst-42"))
    }

    @Test("An unknown or inactive key is rejected with the server's reason")
    func rejected() async {
        let json = #"{"activated":false,"error":"license_key not found.","instance":null}"#
        let validator = LemonSqueezyValidator(transport: Self.transport(json))
        let result = await validator.activate(licenseKey: "bad", instanceName: "Mac")
        #expect(result == .rejected(reason: "license_key not found."))
    }

    @Test("A transport failure surfaces as unreachable, never a crash")
    func unreachable() async {
        let validator = LemonSqueezyValidator(transport: { _ in
            throw URLError(.notConnectedToInternet)
        })
        guard case .unreachable = await validator.activate(licenseKey: "K", instanceName: "Mac")
        else {
            Issue.record("expected unreachable")
            return
        }
    }

    @Test("Each endpoint posts its own fields, form-encoded, to its own path")
    func requestShape() async {
        final class Box: @unchecked Sendable { var requests: [URLRequest] = [] }
        let box = Box()
        let validator = LemonSqueezyValidator(transport: { request in
            box.requests.append(request)
            let body = #"{"activated":true,"valid":true,"instance":{"id":"i-1"}}"#
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        })
        _ = await validator.activate(licenseKey: "ABC", instanceName: "My Mac")
        _ = await validator.validate(licenseKey: "ABC", instanceID: "i-1")

        let bodies = box.requests.map {
            String(bytes: $0.httpBody ?? Data(), encoding: .utf8) ?? ""
        }
        #expect(box.requests.allSatisfy { $0.httpMethod == "POST" })
        #expect(box.requests.first?.url?.lastPathComponent == "activate")
        #expect(box.requests.last?.url?.lastPathComponent == "validate")
        #expect(bodies.first?.contains("license_key=ABC") == true)
        #expect(bodies.first?.contains("instance_name=My%20Mac") == true)
        // formEncoded percent-encodes everything non-alphanumeric, so the
        // dash arrives as %2D — valid form encoding, just conservative.
        #expect(bodies.last?.contains("instance_id=i%2D1") == true)
    }

    @Test("Activation records what Lemon Squeezy issued, stamped with the clock")
    func serviceRecordsActivation() async {
        let stamp = Date(timeIntervalSince1970: 1_000)
        let service = LicenseActivationService(
            validator: LemonSqueezyValidator(transport: Self.transport(Self.activatedJSON)),
            now: { stamp })
        let outcome = await service.activate(licenseKey: "K", instanceName: "Mac")
        #expect(
            outcome
                == .activated(
                    LicenseActivationRecord(
                        licenseKey: "K", instanceID: "inst-42",
                        activatedAt: stamp, lastValidatedAt: stamp)))
    }

    /// The whole point of dropping the embedded signing key: nothing in the
    /// build can produce an entitlement Lemon Squeezy did not grant.
    @Test("A rejected key never produces a record")
    func rejectedKeyProducesNoRecord() async {
        let json = #"{"activated":false,"error":"refunded","instance":null}"#
        let service = LicenseActivationService(
            validator: LemonSqueezyValidator(transport: Self.transport(json)))
        #expect(
            await service.activate(licenseKey: "K", instanceName: "Mac")
                == .rejected(reason: "refunded"))
    }

    @Test("A confirmed refresh advances the grace clock without changing identity")
    func refreshConfirms() async {
        let activated = Date(timeIntervalSince1970: 0)
        let checked = Date(timeIntervalSince1970: 9_000)
        let service = LicenseActivationService(
            validator: LemonSqueezyValidator(transport: Self.transport(Self.validJSON)),
            now: { checked })
        let record = LicenseActivationRecord(
            licenseKey: "K", instanceID: "i-1",
            activatedAt: activated, lastValidatedAt: activated)
        guard case .confirmed(let refreshed) = await service.refresh(record) else {
            Issue.record("expected confirmed")
            return
        }
        #expect(refreshed.lastValidatedAt == checked)
        #expect(refreshed.activatedAt == activated)
        #expect(refreshed.instanceID == "i-1")
    }

    /// A shape change at Lemon Squeezy's end must never read as "no". Before
    /// this, any decodable body that failed the endpoint's check was reported
    /// as a rejection — which would have revoked Pro for every paying user the
    /// day their response format shifted.
    @Test("A decodable but unrecognized body is unreachable, never a rejection")
    func unrecognizedBodyDoesNotRevoke() async {
        for json in [#"{}"#, #"{"instance":{"id":"i-1"}}"#, #"{"meta":{"page":1}}"#] {
            let validator = LemonSqueezyValidator(transport: Self.transport(json))
            guard case .unreachable = await validator.validate(licenseKey: "K", instanceID: "i-1")
            else {
                Issue.record("unrecognized body \(json) must not revoke")
                return
            }
        }
    }

    /// `activated: true` with no instance is a broken payload, not a grant and
    /// not a denial.
    @Test("A success flag without an instance id is unreachable")
    func successWithoutInstanceIsUnreachable() async {
        let validator = LemonSqueezyValidator(
            transport: Self.transport(#"{"activated":true}"#))
        guard case .unreachable = await validator.activate(licenseKey: "K", instanceName: "Mac")
        else {
            Issue.record("a success flag with no instance must not be treated as activated")
            return
        }
    }

    @Test("An explicit false flag still rejects, with or without a reason")
    func explicitFalseStillRejects() async {
        let validator = LemonSqueezyValidator(
            transport: Self.transport(#"{"valid":false}"#))
        #expect(
            await validator.validate(licenseKey: "K", instanceID: "i-1")
                == .rejected(reason: "License key is not active"))
    }

    @Test("Deactivation posts the instance to /deactivate and confirms")
    func deactivateShapeAndResult() async {
        final class Box: @unchecked Sendable { var request: URLRequest? }
        let box = Box()
        let validator = LemonSqueezyValidator(transport: { request in
            box.request = request
            return (
                Data(#"{"deactivated":true}"#.utf8),
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        })
        let result = await validator.deactivate(licenseKey: "ABC", instanceID: "i-1")
        let body = String(bytes: box.request?.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(box.request?.url?.lastPathComponent == "deactivate")
        #expect(body.contains("license_key=ABC"))
        #expect(body.contains("instance_id=i%2D1"))
        #expect(result == .confirmed(instanceID: "i-1"))
    }

    // MARK: - Store/product identity pinning

    /// The one place the literal identity is asserted. These are the public
    /// identifiers the hosted checkout (`LemonSqueezyStore.checkoutURL`) embeds
    /// for the live Gancho Pro product. If this fails, the pin was retuned —
    /// verify the checkout page and the constants still name the same product.
    @Test("The pinned identity names the live Gancho store and product")
    func pinnedIdentityIsTheLiveProduct() {
        #expect(LemonSqueezyValidator.expectedStoreID == 408_765)
        #expect(LemonSqueezyValidator.expectedProductID == 1_178_223)
    }

    /// The public License API accepts keys from every Lemon Squeezy store, so
    /// a merely-valid foreign key must never mint a Gancho entitlement.
    @Test("A valid key for someone else's product activates nothing")
    func foreignKeyDoesNotActivate() async {
        let json =
            #"{"activated":true,"instance":{"id":"inst-42"},"#
            + #""meta":{"store_id":999,"product_id":111}}"#
        let validator = LemonSqueezyValidator(transport: Self.transport(json))
        #expect(
            await validator.activate(licenseKey: "K", instanceName: "Mac")
                == .rejected(reason: "That license key is not a Gancho Pro license"))
    }

    @Test("A test-mode key activates nothing, even for the right product")
    func testModeKeyDoesNotActivate() async {
        let json =
            #"{"activated":true,"instance":{"id":"inst-42"},"#
            + #""license_key":{"test_mode":true},"# + Self.ganchoMeta + "}"
        let validator = LemonSqueezyValidator(transport: Self.transport(json))
        guard
            case .rejected = await validator.activate(licenseKey: "K", instanceName: "Mac")
        else {
            Issue.record("a test-mode key must not activate")
            return
        }
    }

    /// Activation has no existing entitlement to protect, so it fails closed:
    /// an answer that names no store grants nothing.
    @Test("An activation answer with no identity activates nothing")
    func identitylessActivationFailsClosed() async {
        let validator = LemonSqueezyValidator(
            transport: Self.transport(#"{"activated":true,"instance":{"id":"inst-42"}}"#))
        guard
            case .rejected = await validator.activate(licenseKey: "K", instanceName: "Mac")
        else {
            Issue.record("an identity-less activation must fail closed")
            return
        }
    }

    /// Revalidation is the opposite trade: a foreign identity is Lemon Squeezy
    /// answering (revoke), while a missing one is a shape change (grace).
    @Test("Refresh revokes a key that names a foreign store")
    func refreshRevokesForeignKey() async {
        let json =
            #"{"valid":true,"instance":{"id":"i-1"},"#
            + #""meta":{"store_id":999,"product_id":111}}"#
        let service = LicenseActivationService(
            validator: LemonSqueezyValidator(transport: Self.transport(json)))
        let record = LicenseActivationRecord(
            licenseKey: "K", instanceID: "i-1",
            activatedAt: .init(timeIntervalSince1970: 0),
            lastValidatedAt: .init(timeIntervalSince1970: 0))
        #expect(
            await service.refresh(record)
                == .revoked(reason: "That license key is not a Gancho Pro license"))
    }

    /// If Lemon Squeezy ever stops sending `meta`, every paying user's next
    /// revalidation hits this path — it must keep grace, not revoke.
    @Test("Refresh keeps grace when a valid answer names no store at all")
    func refreshWithoutIdentityKeepsGrace() async {
        for json in [
            #"{"valid":true,"instance":{"id":"i-1"}}"#,
            #"{"valid":true,"instance":{"id":"i-1"},"meta":{"store_id":408765}}"#
        ] {
            let validator = LemonSqueezyValidator(transport: Self.transport(json))
            guard
                case .unreachable = await validator.validate(licenseKey: "K", instanceID: "i-1")
            else {
                Issue.record("identity-less validity \(json) must keep grace, not revoke")
                return
            }
        }
    }

    @Test("Lemon Squeezy saying no revokes; an unreachable network does not")
    func refreshDistinguishesRevocationFromOutage() async {
        let record = LicenseActivationRecord(
            licenseKey: "K", instanceID: "i-1",
            activatedAt: .init(timeIntervalSince1970: 0),
            lastValidatedAt: .init(timeIntervalSince1970: 0))

        let revoking = LicenseActivationService(
            validator: LemonSqueezyValidator(
                transport: Self.transport(#"{"valid":false,"error":"license_key is disabled."}"#)))
        #expect(
            await revoking.refresh(record) == .revoked(reason: "license_key is disabled."))

        let offline = LicenseActivationService(
            validator: LemonSqueezyValidator(transport: { _ in
                throw URLError(.notConnectedToInternet)
            }))
        guard case .unreachable = await offline.refresh(record) else {
            Issue.record("an outage must never revoke")
            return
        }
    }
}

@Suite("License entitlement policy")
struct LicenseEntitlementPolicyTests {
    private func record(validatedAt: TimeInterval) -> LicenseActivationRecord {
        LicenseActivationRecord(
            licenseKey: "K", instanceID: "i-1",
            activatedAt: Date(timeIntervalSince1970: 0),
            lastValidatedAt: Date(timeIntervalSince1970: validatedAt))
    }

    @Test("No activation means no entitlement")
    func noRecord() {
        #expect(
            LicenseEntitlementPolicy.entitlement(for: nil, now: Date()) == .none)
    }

    @Test("A recently confirmed license is Pro")
    func confirmedIsPro() {
        #expect(
            LicenseEntitlementPolicy.entitlement(
                for: record(validatedAt: 0), now: Date(timeIntervalSince1970: 60)) == .pro)
    }

    /// Someone who paid must not lose Pro on a plane. Grace covers the whole
    /// window; only past its edge does the entitlement lapse.
    @Test("Pro survives an offline stretch right up to the edge of grace")
    func graceHoldsThenLapses() {
        let grace = LicenseEntitlementPolicy.offlineGrace
        let stored = record(validatedAt: 0)
        #expect(
            LicenseEntitlementPolicy.entitlement(
                for: stored, now: Date(timeIntervalSince1970: grace)) == .pro)
        #expect(
            LicenseEntitlementPolicy.entitlement(
                for: stored, now: Date(timeIntervalSince1970: grace + 1)) == .lapsed)
    }

    /// A lapsed record is distinct from no record: the paywall should offer to
    /// reconnect, not to buy something already bought.
    @Test("Lapsed is not the same as never activated")
    func lapsedIsDistinct() {
        let lapsed = LicenseEntitlementPolicy.entitlement(
            for: record(validatedAt: 0),
            now: Date(timeIntervalSince1970: LicenseEntitlementPolicy.offlineGrace * 2))
        #expect(lapsed == .lapsed)
        #expect(lapsed != .none)
    }

    /// A clock moved backwards keeps Pro — a skewed clock is not the user's
    /// fault — but it must NOT postpone the next check, or a refunded license
    /// would keep working for as long as the clock stayed wrong.
    @Test("A backwards clock keeps Pro but is due for revalidation immediately")
    func backwardsClockIsSafe() {
        let stored = record(validatedAt: 10_000)
        let past = Date(timeIntervalSince1970: 0)
        #expect(LicenseEntitlementPolicy.entitlement(for: stored, now: past) == .pro)
        #expect(LicenseEntitlementPolicy.needsRevalidation(stored, now: past))
    }

    @Test("Revalidation is due only once the interval has elapsed")
    func revalidationSchedule() {
        let interval = LicenseEntitlementPolicy.revalidationInterval
        let stored = record(validatedAt: 0)
        #expect(
            !LicenseEntitlementPolicy.needsRevalidation(
                stored, now: Date(timeIntervalSince1970: interval - 1)))
        #expect(
            LicenseEntitlementPolicy.needsRevalidation(
                stored, now: Date(timeIntervalSince1970: interval)))
    }
}
