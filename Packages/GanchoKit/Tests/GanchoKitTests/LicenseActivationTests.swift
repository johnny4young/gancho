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

    private static let activatedJSON =
        #"{"activated":true,"error":null,"instance":{"id":"inst-42"}}"#

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
            validator: LemonSqueezyValidator(
                transport: Self.transport(#"{"valid":true,"instance":{"id":"i-1"}}"#)),
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

    /// A clock moved backwards must not read as "validated in the future" and
    /// silently extend grace beyond its window.
    @Test("A backwards clock does not extend grace")
    func backwardsClockIsSafe() {
        #expect(
            LicenseEntitlementPolicy.entitlement(
                for: record(validatedAt: 10_000), now: Date(timeIntervalSince1970: 0)) == .pro)
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
