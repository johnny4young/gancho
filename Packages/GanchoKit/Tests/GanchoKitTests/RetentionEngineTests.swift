import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("Retention — windows, sensitive expiry, pins, counters")
struct RetentionEngineTests {
    let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore() throws -> (GRDBClipboardStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("retention-\(UUID().uuidString)", isDirectory: true)
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: dir))
        try store.migrate()
        return (store, dir)
    }

    private func insert(
        _ store: GRDBClipboardStore, preview: String, age: TimeInterval,
        kind: ClipContentKind = .text, pinned: Bool = false, sensitive: Bool = false,
        expiresAt: Date? = nil, content: ClipContent? = nil
    ) async throws {
        try await store.insert(
            ClipItem(
                createdAt: now.addingTimeInterval(-age), kind: kind, preview: preview,
                contentHash: "h-\(preview)", isPinned: pinned, isSensitive: sensitive,
                expiresAt: expiresAt),
            content: content ?? .text(preview))
    }

    @Test("Global window prunes old items and keeps fresh ones")
    func globalWindow() async throws {
        let (store, _) = try makeStore()
        try await insert(store, preview: "ancient", age: 40 * 86_400)
        try await insert(store, preview: "recent", age: 86_400)

        let summary = try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(global: .month), now: now)

        #expect(summary.byGlobalWindow == 1)
        #expect(try await store.items().map(\.preview) == ["recent"])
    }

    @Test("Never window keeps everything")
    func neverKeepsAll() async throws {
        let (store, _) = try makeStore()
        try await insert(store, preview: "ancient", age: 400 * 86_400)

        let summary = try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(global: .never), now: now)

        #expect(summary.totalRowsPurged == 0)
        #expect(try await store.count() == 1)
    }

    @Test("Per-kind window overrides the global (7d images, 90d text)")
    func perKindOverride() async throws {
        let (store, _) = try makeStore()
        try await insert(store, preview: "old image", age: 10 * 86_400, kind: .image)
        try await insert(store, preview: "old text", age: 10 * 86_400)

        let policy = RetentionPolicy(global: .quarter, perKind: [.image: .week])
        let summary = try await RetentionEngine(store: store).runPurge(policy: policy, now: now)

        #expect(summary.byKindWindow == 1)
        #expect(try await store.items().map(\.preview) == ["old text"])
    }

    @Test("Sensitive items self-destruct after their lifetime (default 10 min)")
    func sensitiveExpiry() async throws {
        let (store, _) = try makeStore()
        try await insert(store, preview: "fresh secret", age: 300, sensitive: true)
        try await insert(store, preview: "stale secret", age: 900, sensitive: true)
        try await insert(store, preview: "normal", age: 900)

        let summary = try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(), now: now)

        #expect(summary.sensitiveExpired == 1)
        #expect(
            try await store.items().map(\.preview).sorted() == ["fresh secret", "normal"])
    }

    @Test("Sensitive lifetime is configurable")
    func sensitiveLifetimeConfigurable() async throws {
        let (store, _) = try makeStore()
        try await insert(store, preview: "secret", age: 300, sensitive: true)

        let strict = RetentionPolicy(sensitiveLifetime: 60)
        try await RetentionEngine(store: store).runPurge(policy: strict, now: now)

        #expect(try await store.count() == 0)
    }

    @Test("Per-item expiresAt wins regardless of windows")
    func ownExpiryDate() async throws {
        let (store, _) = try makeStore()
        try await insert(
            store, preview: "timed", age: 60, expiresAt: now.addingTimeInterval(-1))

        let summary = try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(global: .never), now: now)

        #expect(summary.expiredByOwnDate == 1)
        #expect(try await store.count() == 0)
    }

    @Test("Pins never expire — not by window, lifetime, or own date")
    func pinsAreExempt() async throws {
        let (store, _) = try makeStore()
        try await insert(store, preview: "pinned old", age: 400 * 86_400, pinned: true)
        try await insert(
            store, preview: "pinned secret", age: 9_000, pinned: true, sensitive: true)
        try await insert(
            store, preview: "pinned timed", age: 60, pinned: true,
            expiresAt: now.addingTimeInterval(-1))

        let policy = RetentionPolicy(global: .day)
        let summary = try await RetentionEngine(store: store).runPurge(policy: policy, now: now)

        #expect(summary.totalRowsPurged == 0)
        #expect(try await store.count() == 3)
    }

    @Test("Purges sweep orphaned blobs and log counters")
    func orphanSweepAndCounters() async throws {
        let (store, dir) = try makeStore()
        let png = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        )!
        try await insert(
            store, preview: "old image", age: 40 * 86_400, kind: .image,
            content: .binary(data: png, typeIdentifier: "public.png"))

        let summary = try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(global: .month), now: now)

        #expect(summary.byGlobalWindow == 1)
        #expect(summary.orphanedBlobsRemoved == 1)
        let leftover = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0 != "thumbnails" }
        #expect(leftover.isEmpty)

        // Privacy Center counter: totals since a week ago include this run.
        let counted = try await store.purgedItemCount(
            since: now.addingTimeInterval(-7 * 86_400))
        #expect(counted == 1)
    }

    @Test("Purges never delete a blob a surviving clip still shares")
    func purgeKeepsSharedBlobs() async throws {
        let (store, dir) = try makeStore()
        let png = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        )!
        // Same bytes → one content-addressed blob file shared by both rows
        // (distinct contentHash values keep the rows separate).
        try await insert(
            store, preview: "old copy", age: 40 * 86_400, kind: .image,
            content: .binary(data: png, typeIdentifier: "public.png"))
        try await insert(
            store, preview: "fresh copy", age: 86_400, kind: .image,
            content: .binary(data: png, typeIdentifier: "public.png"))

        let engine = RetentionEngine(store: store)
        let first = try await engine.runPurge(policy: RetentionPolicy(global: .month), now: now)

        // The old row went, but the fresh row still references the blob.
        #expect(first.byGlobalWindow == 1)
        #expect(first.orphanedBlobsRemoved == 0, "a shared blob must survive")
        let afterFirst = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0 != "thumbnails" }
        #expect(afterFirst.count == 1)

        // Once the LAST referencing row is purged the blob goes too.
        let later = now.addingTimeInterval(40 * 86_400)
        let second = try await engine.runPurge(policy: RetentionPolicy(global: .month), now: later)
        #expect(second.byGlobalWindow == 1)
        #expect(second.orphanedBlobsRemoved == 1)
        let afterSecond = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0 != "thumbnails" }
        #expect(afterSecond.isEmpty)
    }

    @Test("Purges tombstone synced rows so deletions propagate; unsynced rows leave none")
    func purgeTombstonesSyncedRows() async throws {
        let (store, _) = try makeStore()
        let syncedSecret = ClipItem(
            createdAt: now.addingTimeInterval(-900), preview: "synced secret",
            contentHash: "h-ss", isSensitive: true)
        let unsyncedSecret = ClipItem(
            createdAt: now.addingTimeInterval(-900), preview: "local secret",
            contentHash: "h-us", isSensitive: true)
        let survivor = ClipItem(
            createdAt: now.addingTimeInterval(-60), preview: "fresh", contentHash: "h-f")
        try await store.insert(syncedSecret, content: .text("synced secret"))
        try await store.insert(unsyncedSecret, content: .text("local secret"))
        try await store.insert(survivor, content: .text("fresh"))
        try await store.markUploaded(id: syncedSecret.id, systemFields: Data([1]))

        let summary = try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(), now: now)

        #expect(summary.sensitiveExpired == 2)
        #expect(try await store.items().map(\.preview) == ["fresh"])
        #expect(
            try await store.pendingDeletionRecordIDs() == [syncedSecret.id.uuidString],
            "only rows with a cloud record need a tombstone")
    }

    @Test("Every purge clause tombstones its synced victims")
    func allPurgeClausesTombstone() async throws {
        let (store, _) = try makeStore()
        // One synced victim per clause: own expiry date, sensitive lifetime,
        // per-kind window, global window.
        let byOwnDate = ClipItem(
            createdAt: now.addingTimeInterval(-60), preview: "timed", contentHash: "h-t",
            expiresAt: now.addingTimeInterval(-1))
        let sensitive = ClipItem(
            createdAt: now.addingTimeInterval(-900), preview: "secret", contentHash: "h-s",
            isSensitive: true)
        let oldImage = ClipItem(
            createdAt: now.addingTimeInterval(-10 * 86_400), kind: .image, preview: "img",
            contentHash: "h-i")
        let oldText = ClipItem(
            createdAt: now.addingTimeInterval(-40 * 86_400), preview: "old", contentHash: "h-o")
        for item in [byOwnDate, sensitive, oldImage, oldText] {
            try await store.insert(item, content: .text(item.preview))
            try await store.markUploaded(id: item.id, systemFields: Data([1]))
        }

        let policy = RetentionPolicy(global: .month, perKind: [.image: .week])
        let summary = try await RetentionEngine(store: store).runPurge(policy: policy, now: now)

        #expect(summary.totalRowsPurged == 4)
        #expect(try await store.count() == 0)
        let tombstones = Set(try await store.pendingDeletionRecordIDs())
        let expected = Set([byOwnDate, sensitive, oldImage, oldText].map(\.id.uuidString))
        #expect(tombstones == expected)
    }

    @Test("Retention policy persists through UserDefaults")
    func policyRoundTrip() throws {
        let suite = "retention-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let policy = RetentionPolicy(
            global: .week, perKind: [.image: .day], sensitiveLifetime: 120)
        policy.save(to: defaults)

        #expect(RetentionPolicy.load(from: defaults) == policy)
    }
}
