import Foundation
import Testing

@testable import GanchoKit

private actor DelayedLicenseTransport {
    private let delayedPath: String
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    init(delayedPath: String) { self.delayedPath = delayedPath }

    func waitUntilPending() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        pending?.resume()
        pending = nil
    }

    func response(_ request: URLRequest) async -> (Data, URLResponse) {
        if request.url?.lastPathComponent == delayedPath {
            await withCheckedContinuation { continuation in
                pending = continuation
                waiter?.resume()
                waiter = nil
            }
        }
        let path = request.url?.lastPathComponent
        let json = path == "activate" ? Self.activated : #"{"valid":false,"deactivated":true}"#
        return (
            Data(json.utf8),
            HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }

    static let activated =
        #"{"activated":true,"instance":{"id":"new-instance"},"#
        + #""meta":{"store_id":\#(LemonSqueezyValidator.expectedStoreID),"#
        + #""product_id":\#(LemonSqueezyValidator.expectedProductID)}}"#
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
