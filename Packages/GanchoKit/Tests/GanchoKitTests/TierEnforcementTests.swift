import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("Free tier — archive, never delete")
struct TierEnforcementTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("tier-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    private func seed(_ store: GRDBClipboardStore, count: Int, ageDays: Double = 0) async throws {
        let entries = (0..<count).map { index -> (ClipItem, ClipContent?) in
            let item = ClipItem(
                createdAt: now.addingTimeInterval(-ageDays * 86_400 + Double(index)),
                preview: "clip \(index)", contentHash: "h-\(ageDays)-\(index)")
            return (item, .text("clip \(index)"))
        }
        try await store.importBatch(entries)
    }

    @Test("Items beyond the free item ceiling archive — hidden from lists, NOT deleted")
    func countOverflowArchives() async throws {
        let store = try makeStore()
        let total = FreeTierLimits.historyItems + 20
        try await seed(store, count: total)

        let summary = try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(summary.archived == 20)
        #expect(
            try await store.count() == FreeTierLimits.historyItems, "list count hides archived")
        #expect(try await store.archivedCount() == 20)
        // Export still carries EVERYTHING — no data hostage.
        let export = try await store.exportJSON()
        let object = try JSONSerialization.jsonObject(with: export) as? [String: Any]
        #expect((object?["clips"] as? [[String: Any]])?.count == total)
    }

    @Test("Items older than the free history window archive")
    func ageOverflowArchives() async throws {
        let store = try makeStore()
        let windowDays = FreeTierLimits.historyDays / 86_400
        try await seed(store, count: 5, ageDays: windowDays + 3)  // beyond the window
        try await seed(store, count: 5, ageDays: 1)  // within it

        let summary = try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(summary.archived == 5)
        #expect(try await store.count() == 5)
    }

    @Test("Pins and board members never archive")
    func pinsExempt() async throws {
        let store = try makeStore()
        let windowDays = FreeTierLimits.historyDays / 86_400
        let pinned = ClipItem(
            createdAt: now.addingTimeInterval(-(windowDays + 30) * 86_400), preview: "pinned",
            contentHash: "hp", isPinned: true)
        try await store.insert(pinned, content: .text("pinned"))
        try await seed(store, count: 3, ageDays: windowDays + 3)

        try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(try await store.items().map(\.preview).contains("pinned"))
    }

    @Test("Upgrading to Pro releases every archived clip")
    func proReleases() async throws {
        let store = try makeStore()
        let total = FreeTierLimits.historyItems + 10
        try await seed(store, count: total)
        try await TierEnforcement(store: store).enforce(tier: .free, now: now)
        #expect(try await store.archivedCount() == 10)

        let summary = try await TierEnforcement(store: store).enforce(tier: .pro, now: now)

        #expect(summary.released == 10)
        #expect(try await store.archivedCount() == 0)
        #expect(try await store.count() == total)
    }

    @Test("Archived clips do not surface in search")
    func archivedHiddenFromSearch() async throws {
        let store = try makeStore()
        let windowDays = FreeTierLimits.historyDays / 86_400
        try await seed(store, count: 3, ageDays: windowDays + 3)
        try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(try await store.search(ClipSearchQuery(text: "clip")).isEmpty)
    }

    @Test("Tier persists and defaults to free")
    func tierRoundTrip() throws {
        let suite = "tier-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(UserTier.load(from: defaults) == .free)
        UserTier.pro.save(to: defaults)
        #expect(UserTier.load(from: defaults) == .pro)
    }

    @Test("Free AI-title taste budget counts down and floors at zero")
    func freeAITitleTasteBudget() {
        #expect(FreeTierLimits.freeAITitlesRemaining(used: 0) == FreeTierLimits.freeAITitleTaste)
        #expect(
            FreeTierLimits.freeAITitlesRemaining(used: 10)
                == FreeTierLimits.freeAITitleTaste - 10)
        #expect(FreeTierLimits.freeAITitlesRemaining(used: FreeTierLimits.freeAITitleTaste) == 0)
        #expect(FreeTierLimits.freeAITitlesRemaining(used: 999) == 0)
    }
}
