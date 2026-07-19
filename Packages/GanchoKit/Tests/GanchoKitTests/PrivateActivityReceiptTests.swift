import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Private activity receipt")
struct PrivateActivityReceiptTests {
    private func makeStore() throws -> (GRDBClipboardStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "private-receipt-tests-\(UUID().uuidString)", isDirectory: true)
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: directory))
        try store.migrate()
        return (store, directory)
    }

    @Test("Capture, reuse, skip, protection, and expiry totals stay grouped and factual")
    func recordsGroupedTotals() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try await store.recordPrivateCapture(
            sourceAppBundleID: "com.apple.Safari", count: 2, at: now)
        try await store.recordPrivateCapture(
            sourceAppBundleID: "com.apple.dt.Xcode", count: 1, at: now)
        try await store.recordPrivateReuse(
            targetAppBundleID: "com.apple.Safari", itemCount: 3, at: now)
        try await store.recordPrivateReuse(targetAppBundleID: nil, itemCount: 2, at: now)
        try await store.recordPrivateSkippedCapture(isProtected: false, count: 4, at: now)
        try await store.recordPrivateSkippedCapture(isProtected: true, count: 2, at: now)
        try await store.recordPrivateSensitiveExpiry(count: 5, at: now)

        let receipt = try await store.privateActivityReceipt(now: now)
        #expect(receipt.captures == 3)
        #expect(receipt.reusedItems == 5)
        #expect(receipt.skippedCaptures == 6)
        #expect(receipt.protectedCaptures == 2)
        #expect(receipt.sensitiveItemsExpired == 5)
        #expect(
            receipt.appStats.contains(
                PrivateActivityAppStat(
                    bundleID: "com.apple.Safari", captures: 2, reuses: 3)))
        #expect(
            receipt.appStats.contains(
                PrivateActivityAppStat(
                    bundleID: "com.apple.dt.Xcode", captures: 1, reuses: 0)))
        #expect(
            receipt.appStats.contains(
                PrivateActivityAppStat(bundleID: nil, captures: 0, reuses: 2)))
    }

    @Test("Concurrent increments are atomic")
    func concurrentIncrementsAreAtomic() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    try await store.recordPrivateCapture(
                        sourceAppBundleID: "com.example.Editor", at: now)
                }
            }
            try await group.waitForAll()
        }

        let receipt = try await store.privateActivityReceipt(now: now)
        #expect(receipt.captures == 100)
        #expect(
            receipt.appStats == [
                PrivateActivityAppStat(
                    bundleID: "com.example.Editor", captures: 100, reuses: 0)
            ])
    }

    @Test("Rows older than thirteen months are pruned while the boundary day survives")
    func rollingRetention() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z"))
        let expired = try #require(
            ISO8601DateFormatter().date(from: "2025-06-14T12:00:00Z"))
        let boundary = try #require(
            ISO8601DateFormatter().date(from: "2025-06-15T12:00:00Z"))

        try await store.recordPrivateCapture(
            sourceAppBundleID: "com.example.Old", count: 9, at: expired)
        try await store.recordPrivateCapture(
            sourceAppBundleID: "com.example.Boundary", count: 2, at: boundary)
        try await store.recordPrivateCapture(
            sourceAppBundleID: "com.example.Current", count: 1, at: now)

        let receipt = try await store.privateActivityReceipt(now: now)
        #expect(receipt.captures == 3)
        #expect(
            receipt.retainedSince
                == ISO8601DateFormatter().date(from: "2025-06-15T00:00:00Z"))
        #expect(!receipt.appStats.contains { $0.bundleID == "com.example.Old" })
        let rows = try await store.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip_app_stats") ?? -1
        }
        #expect(rows == 2)
    }

    @Test("Clear erases only the receipt")
    func clearPreservesHistory() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipItem(preview: "keep me", contentHash: "private-receipt-keep")
        try await store.insert(item, content: .text("keep me"))
        try await store.recordPrivateCapture(sourceAppBundleID: "com.example.Editor", count: 7)
        try await store.recordPrivateSensitiveExpiry(count: 3)

        try await store.clearPrivateActivityReceipt()

        #expect(try await store.privateActivityReceipt().captures == 0)
        #expect(try await store.privateActivityReceipt().sensitiveItemsExpired == 0)
        #expect(try await store.count() == 1)
        #expect(try await store.content(for: item.id) == .text("keep me"))
    }

    @Test("Schema and bounded identifiers cannot carry clipboard content")
    func contentFreeBoundedSchema() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hostileBundleID = "com.example.\n" + String(repeating: "x", count: 1_000)

        try await store.recordPrivateCapture(
            sourceAppBundleID: hostileBundleID, count: .max)
        try await store.recordPrivateReuse(
            targetAppBundleID: "__gancho.aggregate__", itemCount: 1)
        try await store.recordPrivateReuse(
            targetAppBundleID: "copied password: correct horse battery staple", itemCount: 1)

        let (columns, storedIDs, indexNames) = try await store.writer.read { db in
            let columns = try String.fetchAll(
                db, sql: "SELECT name FROM pragma_table_info('clip_app_stats')")
            let storedIDs = try String.fetchAll(
                db, sql: "SELECT bundleID FROM clip_app_stats ORDER BY bundleID")
            let indexNames = try String.fetchAll(
                db, sql: "SELECT name FROM pragma_index_list('clip_app_stats')")
            return (columns, storedIDs, indexNames)
        }

        #expect(
            Set(columns) == [
                "bundleID", "day", "captures", "pastes", "skippedCaptures",
                "protectedCaptures", "sensitiveItemsExpired"
            ])
        #expect(!columns.contains { $0.localizedCaseInsensitiveContains("content") })
        #expect(!columns.contains { $0.localizedCaseInsensitiveContains("title") })
        #expect(!columns.contains { $0.localizedCaseInsensitiveContains("query") })
        #expect(storedIDs.allSatisfy { $0.count <= 255 && !$0.contains("\n") })
        #expect(storedIDs == ["__gancho.unknown__"])
        #expect(!storedIDs.contains { $0.contains("password") })
        #expect(indexNames.contains("idx_clip_app_stats_day"))
        let receipt = try await store.privateActivityReceipt()
        #expect(receipt.captures == 1_000_000)
        #expect(
            receipt.appStats == [
                PrivateActivityAppStat(bundleID: nil, captures: 1_000_000, reuses: 2)
            ])
    }

    @Test("Cross-app totals saturate instead of overflowing SQLite SUM")
    func aggregateTotalsSaturate() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let maximumRowCounter = 9_000_000_000_000_000

        try await store.writer.write { db in
            for index in 0..<1_025 {
                try db.execute(
                    sql: """
                        INSERT INTO clip_app_stats (bundleID, day, captures, pastes)
                        VALUES (?, '2026-07-15', ?, 0)
                        """,
                    arguments: ["com.example.App\(index)", maximumRowCounter])
            }
        }

        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z"))
        let receipt = try await store.privateActivityReceipt(now: now)
        #expect(receipt.captures == .max)
        #expect(receipt.appStats.count == 1_025)
        #expect(receipt.appStats.allSatisfy { $0.captures == maximumRowCounter })
    }

    @Test("v20 upgrades existing v17 counters without data loss")
    func upgradesV17Rows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "private-receipt-v17-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: directory))
        try store.migrate(upTo: "v17-frecency-boards-insights")
        try await store.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clip_app_stats (bundleID, day, captures, pastes)
                    VALUES ('com.example.Legacy', '2026-07-15', 4, 3)
                    """)
        }

        try store.migrate()
        let now = try #require(
            ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z"))
        let receipt = try await store.privateActivityReceipt(now: now)
        #expect(receipt.captures == 4)
        #expect(receipt.reusedItems == 3)
        #expect(receipt.skippedCaptures == 0)
        #expect(receipt.protectedCaptures == 0)
        #expect(receipt.sensitiveItemsExpired == 0)
    }
}
