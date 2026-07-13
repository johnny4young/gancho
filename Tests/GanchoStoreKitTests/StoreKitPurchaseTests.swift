import AppKit
import Foundation
import GanchoKit
import StoreKit
import StoreKitTest
import Testing

@MainActor
@Suite("StoreKit purchase and entitlement integration", .serialized)
struct StoreKitPurchaseTests {
    @Test("Lifetime purchase unlocks Pro and reports the tier change")
    func purchaseUnlocksPro() async throws {
        let session = try makeSession()
        defer { reset(session) }
        let purchaseWindow = makePurchaseWindow()
        defer { purchaseWindow.close() }
        let handler = StoreKitPurchaseHandler()
        var reportedTiers = [UserTier]()
        handler.onTierChange = { reportedTiers.append($0) }

        #expect(await handler.currentTier() == .free)
        #expect(try await handler.purchase(.lifetime))
        #expect(await eventuallyTier(.pro, from: handler))
        #expect(reportedTiers.contains(.pro))
        #expect(session.allTransactions().map(\.productIdentifier) == [ProCatalog.lifetime.id])
    }

    @Test("Cancelled purchase never unlocks Pro")
    func cancelledPurchaseStaysFree() async throws {
        let session = try makeSession()
        defer { reset(session) }
        let purchaseWindow = makePurchaseWindow()
        defer { purchaseWindow.close() }
        let handler = StoreKitPurchaseHandler()

        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        #expect(try await !handler.purchase(.lifetime))
        #expect(await handler.currentTier() == .free)
    }

    @Test("Unverified local transaction never unlocks Pro")
    func unverifiedTransactionStaysFree() async throws {
        let session = try makeSession()
        defer { reset(session) }
        let handler = StoreKitPurchaseHandler()

        try await session.setSimulatedError(
            .verification(.invalidSignature), forAPI: .verification)
        try await session.buyProduct(identifier: ProCatalog.lifetime.id)

        #expect(await handler.currentTier() == .free)
    }

    @Test("Restore and current entitlement reflect the local transaction")
    func restoreReadsCurrentEntitlement() async throws {
        let session = try makeSession()
        defer { reset(session) }
        let handler = StoreKitPurchaseHandler()

        try await session.buyProduct(identifier: ProCatalog.lifetime.id)

        #expect(await eventuallyTier(.pro, from: handler))
        #expect(try await handler.restorePurchases())
        #expect(await handler.currentTier() == .pro)
    }

    private func makeSession() throws -> SKTestSession {
        let configurationURL = try #require(
            Bundle(for: StoreKitTestBundleToken.self).url(
                forResource: "Gancho", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configurationURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    private func reset(_ session: SKTestSession) {
        session.clearTransactions()
        session.resetToDefaultState()
    }

    private func makePurchaseWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "StoreKit Test Host"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        return window
    }

    private func eventuallyTier(
        _ expected: UserTier,
        from handler: StoreKitPurchaseHandler
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        repeat {
            if await handler.currentTier() == expected { return true }
            try? await clock.sleep(for: .milliseconds(50))
        } while clock.now < deadline
        return false
    }
}

private final class StoreKitTestBundleToken {}
