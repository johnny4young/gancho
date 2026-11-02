import ClipboardCore
import Foundation
import GRDB
import Testing

@testable import GanchoAppCore
@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Keyboard Up next — one log for every app, off unless turned on")
struct KeyboardUpNextTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let clip = UUID()

    private func makeStore() throws -> GRDBClipboardStore {
        try GRDBClipboardStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("keyboard-up-next-\(UUID().uuidString)", isDirectory: true))
    }

    private func events(_ count: Int, of id: UUID? = nil) -> [PasteEvent] {
        (0..<count).map {
            PasteEvent(clipID: id ?? clip, pastedAt: now.addingTimeInterval(TimeInterval(-60 * $0)))
        }
    }

    @Test("Two inserts make a habit; one is a coincidence")
    func needsTwoInserts() {
        #expect(
            KeyboardUpNext.clipID(events: [], isBrowsing: true, firstRowID: nil, now: now) == nil)
        #expect(
            KeyboardUpNext.clipID(events: events(1), isBrowsing: true, firstRowID: nil, now: now)
                == nil)
        #expect(
            KeyboardUpNext.clipID(events: events(2), isBrowsing: true, firstRowID: nil, now: now)
                == clip)
    }

    @Test("Only on the plain recent list, and never over its own first row")
    func visibility() {
        let many = events(3)
        #expect(
            KeyboardUpNext.clipID(events: many, isBrowsing: false, firstRowID: nil, now: now) == nil
        )
        #expect(
            KeyboardUpNext.clipID(events: many, isBrowsing: true, firstRowID: clip, now: now) == nil
        )
        #expect(
            KeyboardUpNext.clipID(events: many, isBrowsing: true, firstRowID: UUID(), now: now)
                == clip)
    }

    @Test("The log target is a shape the paste log accepts, and it round-trips")
    func logTargetIsAccepted() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "hello", contentHash: "hash-hello")
        try await store.insert(item, content: .text("hello"))
        for _ in 0..<2 {
            try await store.recordPasteEvents(
                clipIDs: [item.id], targetBundleID: KeyboardUpNext.logTarget, at: .now)
        }
        let logged = try await store.pasteEvents(
            targetBundleID: KeyboardUpNext.logTarget, now: .now)
        #expect(logged.map(\.clipID) == [item.id, item.id])
        #expect(
            KeyboardUpNext.clipID(events: logged, isBrowsing: true, firstRowID: nil) == item.id)
    }

    @Test("Secrets and masked kinds never reach the log")
    func logRefusesTheProtected() async throws {
        let store = try makeStore()
        var protected = [ClipItem(preview: "x", contentHash: "secret", isSensitive: true)]
        for kind in ClipContentKind.allCases where kind.prefersMaskedPreview {
            protected.append(ClipItem(kind: kind, preview: "x", contentHash: "masked-\(kind)"))
        }
        for item in protected { try await store.insert(item, content: .text("synthetic")) }
        try await store.recordPasteEvents(
            clipIDs: protected.map(\.id), targetBundleID: KeyboardUpNext.logTarget, at: .now)
        // The table itself: the read filter would hide a row that got in.
        let rows = try await store.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM paste_event") ?? -1
        }
        #expect(rows == 0)
    }

    @Test("An insert logs only while the switch is on")
    func logsOnlyWhileOn() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "hello", contentHash: "hash-switch")
        try await store.insert(item, content: .text("hello"))
        let rows = {
            try await store.writer.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM paste_event") ?? -1
            }
        }
        await KeyboardUpNext.logInsert(item.id, in: store, isEnabled: false)
        #expect(try await rows() == 0, "the table, not a filtered read")
        await KeyboardUpNext.logInsert(item.id, in: store, isEnabled: true)
        #expect(try await rows() == 1)
    }

    @Test("An archived clip leaves the log's results")
    func archivedClipIsNotRead() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "hello", contentHash: "hash-archived")
        try await store.insert(item, content: .text("hello"))
        try await store.recordPasteEvents(
            clipIDs: [item.id, item.id], targetBundleID: KeyboardUpNext.logTarget, at: .now)
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [item.id.uuidString])
        }
        #expect(
            try await store.pasteEvents(targetBundleID: KeyboardUpNext.logTarget, now: .now)
                .isEmpty)
    }

    @Test("Off unless turned on, and the switch round-trips")
    func preference() throws {
        let suite = "keyboard-up-next-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!KeyboardUpNextPreference.isEnabled(in: defaults))
        KeyboardUpNextPreference.setEnabled(true, in: defaults)
        #expect(KeyboardUpNextPreference.isEnabled(in: defaults))
        KeyboardUpNextPreference.setEnabled(false, in: defaults)
        #expect(!KeyboardUpNextPreference.isEnabled(in: defaults))
    }
}
