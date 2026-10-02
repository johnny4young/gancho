import Foundation
import Synchronization

@testable import GanchoKit

/// A purchase handler that cannot transact.
struct UnavailablePurchaseHandler: PurchaseHandling {
    init() {}
    var isPurchaseAvailable: Bool { false }
    func availableProducts() async -> [ProProduct] { [] }
    func purchase(_ plan: ProProduct.Plan) async throws -> PurchaseOutcome {
        // Nothing to cancel: this handler cannot transact at all.
        .failed
    }
    func restorePurchases() async throws -> Bool { false }
    func currentTier() async -> UserTier { .free }
}

/// In-memory license token storage.
final class InMemoryLicenseTokenStore: LicenseTokenStore {
    private let storedToken: Mutex<String?>

    init(token: String? = nil) { self.storedToken = Mutex(token) }

    func load() -> String? { storedToken.withLock { $0 } }
    func save(_ token: String) throws { storedToken.withLock { $0 = token } }
    func clear() throws { storedToken.withLock { $0 = nil } }
}
