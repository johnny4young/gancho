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

    @Test("A clip filed on a board (junction membership, v10+) never archives")
    func junctionBoardMembersExempt() async throws {
        let store = try makeStore()
        let windowDays = FreeTierLimits.historyDays / 86_400
        let filed = ClipItem(
            createdAt: now.addingTimeInterval(-(windowDays + 30) * 86_400), preview: "filed",
            contentHash: "hb")
        try await store.insert(filed, content: .text("filed"))
        let board = try await store.createPinboard(name: "Work")
        try await store.assign(clipID: filed.id, toBoard: board.id)
        try await seed(store, count: 3, ageDays: windowDays + 3)

        let summary = try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(summary.archived == 3)
        #expect(try await store.items().map(\.preview).contains("filed"))
    }

    @Test("Sensitive clips never archive — retention owns their lifecycle")
    func sensitiveExempt() async throws {
        let store = try makeStore()
        let windowDays = FreeTierLimits.historyDays / 86_400
        let secret = ClipItem(
            createdAt: now.addingTimeInterval(-(windowDays + 3) * 86_400), preview: "secret",
            contentHash: "hs", isSensitive: true)
        try await store.insert(secret, content: .text("secret"))
        try await seed(store, count: 3, ageDays: windowDays + 3)

        let summary = try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(summary.archived == 3)
        #expect(try await store.items().map(\.preview).contains("secret"))
        #expect(try await store.sensitiveCount() == 1)
    }

    @Test("The item ceiling also skips sensitive and board-member clips")
    func countCeilingSkipsExemptRows() async throws {
        let store = try makeStore()
        let secret = ClipItem(
            createdAt: now.addingTimeInterval(-86_400), preview: "old secret",
            contentHash: "hs2", isSensitive: true)
        try await store.insert(secret, content: .text("old secret"))
        let filed = ClipItem(
            createdAt: now.addingTimeInterval(-86_400 + 1), preview: "old filed",
            contentHash: "hb2")
        try await store.insert(filed, content: .text("old filed"))
        let board = try await store.createPinboard(name: "Work")
        try await store.assign(clipID: filed.id, toBoard: board.id)
        try await seed(store, count: FreeTierLimits.historyItems)  // fills the ceiling

        let summary = try await TierEnforcement(store: store).enforce(tier: .free, now: now)

        #expect(summary.archived == 0)
        #expect(try await store.archivedCount() == 0)
    }

    @Test("Re-copying archived content revives the row into visible history")
    func dedupeRevivesArchivedRow() async throws {
        let store = try makeStore()
        try await seed(store, count: FreeTierLimits.historyItems + 1)
        try await TierEnforcement(store: store).enforce(tier: .free, now: now)
        #expect(try await store.archivedCount() == 1)

        // The archived row is the oldest seed. Re-copying its content must
        // surface the existing row, not swallow the copy into the hidden set.
        let recopy = ClipItem(preview: "clip 0", contentHash: "h-0.0-0")
        let stored = try await store.insert(recopy, content: .text("clip 0"))

        #expect(try await store.archivedCount() == 0)
        #expect(try await store.items().map(\.id).contains(stored.id))
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

    @Test("Free-tier pressure escalates: comfortable → almostFull → reached")
    func freeTierPressureEscalates() {
        // Pro never feels pressure, even at zero room.
        #expect(
            FreeTierLimits.pressure(
                boardsUsed: PinLimits.freeMaxPinboards, snippetsUsed: SnippetLimits.freeMaxSnippets,
                isPro: true) == .comfortable)
        // Empty free account: plenty of room.
        #expect(
            FreeTierLimits.pressure(boardsUsed: 0, snippetsUsed: 0, isPro: false) == .comfortable)
        // One board slot left → almost full (the snippet axis still comfortable).
        #expect(
            FreeTierLimits.pressure(
                boardsUsed: PinLimits.freeMaxPinboards - 1, snippetsUsed: 0, isPro: false)
                == .almostFull)
        // One snippet slot left → almost full (the board axis still comfortable).
        #expect(
            FreeTierLimits.pressure(
                boardsUsed: 0, snippetsUsed: SnippetLimits.freeMaxSnippets - 1, isPro: false)
                == .almostFull)
        // A ceiling hit on either axis → reached.
        #expect(
            FreeTierLimits.pressure(
                boardsUsed: PinLimits.freeMaxPinboards, snippetsUsed: 0, isPro: false) == .reached)
        #expect(
            FreeTierLimits.pressure(
                boardsUsed: 0, snippetsUsed: SnippetLimits.freeMaxSnippets, isPro: false)
                == .reached)
    }
}
