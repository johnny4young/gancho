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

    @Test("Items beyond 500 archive — hidden from lists, NOT deleted")
    func countOverflowArchives() async throws {
        let store = try makeStore()
        try await seed(store, count: 520)

        let summary = try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(summary.archived == 20)
        #expect(try await store.count() == 500, "list count hides archived")
        #expect(try await store.archivedCount() == 20)
        // Export still carries EVERYTHING — no data hostage.
        let export = try await store.exportJSON()
        let object = try JSONSerialization.jsonObject(with: export) as? [String: Any]
        #expect((object?["clips"] as? [[String: Any]])?.count == 520)
    }

    @Test("Items older than 7 days archive")
    func ageOverflowArchives() async throws {
        let store = try makeStore()
        try await seed(store, count: 5, ageDays: 10)
        try await seed(store, count: 5, ageDays: 1)

        let summary = try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(summary.archived == 5)
        #expect(try await store.count() == 5)
    }

    @Test("Pins and board members never archive")
    func pinsExempt() async throws {
        let store = try makeStore()
        let pinned = ClipItem(
            createdAt: now.addingTimeInterval(-30 * 86_400), preview: "pinned",
            contentHash: "hp", isPinned: true)
        try await store.insert(pinned, content: .text("pinned"))
        try await seed(store, count: 3, ageDays: 10)

        try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(try await store.items().map(\.preview).contains("pinned"))
    }

    @Test("Upgrading to Pro releases every archived clip")
    func proReleases() async throws {
        let store = try makeStore()
        try await seed(store, count: 510)
        try await TierEnforcement(store: store).enforce(tier: .free, now: now)
        #expect(try await store.archivedCount() == 10)

        let summary = try await TierEnforcement(store: store).enforce(tier: .pro, now: now)

        #expect(summary.released == 10)
        #expect(try await store.archivedCount() == 0)
        #expect(try await store.count() == 510)
    }

    @Test("Archived clips do not surface in search")
    func archivedHiddenFromSearch() async throws {
        let store = try makeStore()
        try await seed(store, count: 3, ageDays: 10)
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
}
