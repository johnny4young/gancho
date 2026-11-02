import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Paste event log")
struct PasteEventLogTests {
    private let target = "com.apple.dt.Xcode"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() throws -> (GRDBClipboardStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "paste-event-tests-\(UUID().uuidString)", isDirectory: true)
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: directory))
        try store.migrate()
        return (store, directory)
    }

    private func clip(
        _ store: GRDBClipboardStore, kind: ClipContentKind = .text, sensitive: Bool = false
    ) async throws -> UUID {
        let item = ClipItem(
            kind: kind, title: "t", preview: "p", contentHash: UUID().uuidString,
            isSensitive: sensitive)
        return try await store.insert(item, content: .text("body")).id
    }

    @Test("Pastes into one app read back newest first, per app")
    func recordsPerApp() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await clip(store)
        let second = try await clip(store)

        try await store.recordPasteEvents(clipIDs: [first], targetBundleID: target, at: now)
        try await store.recordPasteEvents(
            clipIDs: [second], targetBundleID: target, at: now.addingTimeInterval(60))
        try await store.recordPasteEvents(
            clipIDs: [first], targetBundleID: "com.apple.Safari", at: now)

        let events = try await store.pasteEvents(targetBundleID: target, now: now)
        #expect(events.map(\.clipID) == [second, first])
        #expect(
            try await store.pasteEvents(targetBundleID: "com.apple.Safari", now: now).count == 1)
    }

    @Test("Secrets, masked kinds, unknown clips and malformed bundle ids stay out")
    func skipsProtected() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secret = try await clip(store, sensitive: true)
        let jwt = try await clip(store, kind: .jwt)
        let plain = try await clip(store)

        try await store.recordPasteEvents(
            clipIDs: [secret, jwt, UUID()], targetBundleID: target, at: now)
        try await store.recordPasteEvents(clipIDs: [plain], targetBundleID: "a b", at: now)
        try await store.recordPasteEvents(clipIDs: [plain], targetBundleID: "", at: now)

        let rows = try await store.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM paste_event") ?? -1
        }
        #expect(rows == 0)
    }

    @Test("A clip that turns secret or is deleted leaves the log")
    func followsTheClip() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let turnsSecret = try await clip(store)
        let deleted = try await clip(store)
        let kept = try await clip(store)
        try await store.recordPasteEvents(
            clipIDs: [turnsSecret, deleted, kept], targetBundleID: target, at: now)

        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isSensitive = 1 WHERE id = ?",
                arguments: [turnsSecret.uuidString])
        }
        try await store.delete(id: deleted)

        let rows = try await store.writer.read { db in
            try String.fetchAll(db, sql: "SELECT clipID FROM paste_event")
        }
        #expect(rows == [kept.uuidString])
    }

    @Test("The window prunes old pastes and clear erases the log")
    func windowAndClear() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try await clip(store)
        let old = now.addingTimeInterval(-PasteEventLog.window - 1)
        try await store.recordPasteEvents(clipIDs: [id], targetBundleID: target, at: old)
        #expect(try await store.pasteEvents(targetBundleID: target, now: now).isEmpty)
        try await store.prunePasteEvents(now: now)
        let pruned = try await store.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM paste_event") ?? -1
        }
        #expect(pruned == 0)

        try await store.recordPasteEvents(clipIDs: [id], targetBundleID: target, at: now)
        let rows = try await store.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM paste_event") ?? -1
        }
        #expect(rows == 1)

        try await store.clearPasteEvents()
        #expect(try await store.pasteEvents(targetBundleID: target, now: now).isEmpty)
    }

    @Test("The export carries no paste log")
    func exportLeavesItOut() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try await clip(store)
        try await store.recordPasteEvents(clipIDs: [id], targetBundleID: target, at: now)

        let json = try #require(String(bytes: try await store.exportJSON(), encoding: .utf8))
        #expect(!json.contains(target))
    }
}
