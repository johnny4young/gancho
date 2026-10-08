import Foundation
import Testing

@testable import GanchoKit

private actor DelayedLicenseTransport {
    private let delayedPath: String
    private let delayedKey: String?
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var deactivatedKeys: [String] = []

    init(delayedPath: String, delayedKey: String? = nil) {
        self.delayedPath = delayedPath
        self.delayedKey = delayedKey
    }

    func waitUntilPending() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        pending?.resume()
        pending = nil
    }

    func response(_ request: URLRequest) async -> (Data, URLResponse) {
        let body = String(bytes: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        let selectedKey = delayedKey.map { body.contains("license_key=\($0)") } ?? true
        if request.url?.lastPathComponent == delayedPath && selectedKey {
            await withCheckedContinuation { continuation in
                pending = continuation
                waiter?.resume()
                waiter = nil
            }
        }
        let path = request.url?.lastPathComponent
        let key = Self.licenseKey(in: body)
        if path == "deactivate" { deactivatedKeys.append(key) }
        let json =
            path == "activate"
            ? Self.activated(instance: "instance-\(key)")
            : #"{"valid":false,"deactivated":true}"#
        return (
            Data(json.utf8),
            HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    /// Lemon Squeezy creates a distinct instance per activation.
    static func activated(instance: String) -> String {
        #"{"activated":true,"instance":{"id":"\#(instance)"},"#
            + #""meta":{"store_id":\#(LemonSqueezyValidator.expectedStoreID),"#
            + #""product_id":\#(LemonSqueezyValidator.expectedProductID)}}"#
    }

    private static func licenseKey(in body: String) -> String {
        let field = body.split(separator: "&").first { $0.hasPrefix("license_key=") }
        return field.map { String($0.dropFirst("license_key=".count)) } ?? ""
    }
}

@MainActor
@Suite("License reactivation and stale operation admission")
struct LicenseSessionReactivationTests {
    private func makeHandler(
        store: any LicenseTokenStore, transport: @escaping LemonSqueezyValidator.Transport
    ) -> LicenseKeyPurchaseHandler {
        LicenseKeyPurchaseHandler(
            store: store,
            activation: LicenseActivationService(
                validator: LemonSqueezyValidator(transport: transport)),
            instanceName: "Fixture Mac")
    }

    @Test("Deactivate or revoke then activate a new key on the same handler")
    func reactivate() async {
        for revoke in [false, true] {
            let fake = DelayedLicenseTransport(delayedPath: "never")
            let handler = makeHandler(store: InMemoryLicenseTokenStore()) {
                await fake.response($0)
            }
            #expect(await handler.activateResult(licenseKey: "OLD") == .activated)
            if revoke {
                _ = await handler.recheckNow()
            } else {
                _ = await handler.deactivate()
            }
            #expect(await handler.currentTier() == .free)
            #expect(await handler.activateResult(licenseKey: "NEW") == .activated)
            #expect(await handler.currentTier() == .pro)
        }
    }

    @Test("Delayed old refresh and deactivation replies cannot clear a new activation")
    func staleResponses() async {
        for path in ["validate", "deactivate"] {
            let delayed = DelayedLicenseTransport(delayedPath: path)
            let handler = makeHandler(store: InMemoryLicenseTokenStore()) {
                await delayed.response($0)
            }
            #expect(await handler.activateResult(licenseKey: "OLD") == .activated)
            let old = Task {
                if path == "validate" {
                    _ = await handler.recheckNow()
                } else {
                    _ = await handler.deactivate()
                }
            }
            await delayed.waitUntilPending()
            #expect(await handler.activateResult(licenseKey: "NEW") == .activated)
            await delayed.resume()
            await old.value
            #expect(await handler.currentTier() == .pro)
        }
    }

    @Test("A delayed older activation cannot overwrite the latest activation")
    func staleActivation() async {
        let store = InMemoryLicenseTokenStore()
        let fake = DelayedLicenseTransport(delayedPath: "activate", delayedKey: "OLD")
        let handler = makeHandler(store: store) { await fake.response($0) }
        let old = Task { await handler.activateResult(licenseKey: "OLD") }
        await fake.waitUntilPending()
        #expect(await handler.activateResult(licenseKey: "NEW") == .activated)
        await fake.resume()
        guard case .storageUnavailable = await old.value else {
            Issue.record("the superseded activation must not be admitted")
            return
        }
        #expect(store.load()?.contains("NEW") == true)
        #expect(await handler.currentTier() == .pro)
        // The superseded reply's remote seat is released; the stored one is not.
        #expect(await fake.deactivatedKeys == ["OLD"])
    }

    @Test("Background refresh cannot cancel a pending user activation")
    func refreshDuringActivation() async {
        let store = InMemoryLicenseTokenStore()
        let fake = DelayedLicenseTransport(delayedPath: "activate", delayedKey: "NEW")
        let handler = makeHandler(store: store) { await fake.response($0) }
        #expect(await handler.activateResult(licenseKey: "OLD") == .activated)
        let activation = Task { await handler.activateResult(licenseKey: "NEW") }
        await fake.waitUntilPending()
        _ = await handler.recheckNow()
        await fake.resume()
        #expect(await activation.value == .activated)
        #expect(store.load()?.contains("NEW") == true)
        #expect(await handler.currentTier() == .pro)
    }

    @Test("Failed save and failed readback never release the revocation latch")
    func failedAdmission() async {
        for failSave in [false, true] {
            let store = ReactivationFailureStore()
            let fake = DelayedLicenseTransport(delayedPath: "never")
            let handler = makeHandler(store: store) { await fake.response($0) }
            #expect(await handler.activateResult(licenseKey: "OLD") == .activated)
            _ = await handler.deactivate()
            store.failSave = failSave
            store.failReadback = !failSave
            guard case .storageUnavailable = await handler.activateResult(licenseKey: "NEW") else {
                Issue.record("failed admission must report storage failure")
                return
            }
            // Readback recovers, so only the latch can still be keeping Pro off.
            store.failReadback = false
            #expect(await handler.currentTier() == .free)
        }
    }
}

private final class ReactivationFailureStore: LicenseTokenStore, @unchecked Sendable {
    struct SaveFailure: Error {}
    var failSave = false
    var failReadback = false
    private var token: String?
    func load() -> String? { failReadback ? nil : token }
    func save(_ token: String) throws {
        if failSave { throw SaveFailure() }
        self.token = token
    }
    func clear() throws { token = nil }
}
