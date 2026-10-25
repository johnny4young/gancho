import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Library browse — pages, totals and membership read like the cards show them")
struct LibraryBrowseTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("library-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    private func clip(
        _ name: String, kind: ClipContentKind = .text, minutesAgo: Double, pinned: Bool = false
    ) -> ClipItem {
        ClipItem(
            createdAt: .now.addingTimeInterval(-minutesAgo * 60), kind: kind, preview: name,
            contentHash: name, isPinned: pinned)
    }

    private func insert(_ items: [ClipItem], into store: GRDBClipboardStore) async throws {
        for item in items { try await store.insert(item, content: .text(item.preview)) }
    }

    @Test("Pinned first, then by capture time; Oldest reverses both runs")
    func order() async throws {
        let store = try makeStore()
        let old = clip("old", minutesAgo: 300)
        let new = clip("new", minutesAgo: 1)
        let pinnedOld = clip("pinned old", minutesAgo: 400, pinned: true)
        let pinnedNew = clip("pinned new", minutesAgo: 2, pinned: true)
        try await insert([old, new, pinnedOld, pinnedNew], into: store)
        // Re-using an old clip must not lift it: the groups follow capture time.
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET lastUsedAt = ? WHERE id = ?",
                arguments: [Date.now, old.id.uuidString])
        }

        let newest = try await store.libraryItems(.init(scope: .all), offset: 0, limit: 10)
        #expect(newest.map(\.preview) == ["pinned new", "pinned old", "new", "old"])
        let oldest = try await store.libraryItems(
            .init(scope: .all, oldestFirst: true), offset: 0, limit: 10)
        #expect(oldest.map(\.preview) == ["pinned old", "pinned new", "old", "new"])
        let paged = try await store.libraryItems(.init(scope: .all), offset: 1, limit: 2)
        #expect(paged.map(\.preview) == ["pinned old", "new"])
    }

    @Test("Scope and kinds narrow both the page and the total")
    func scopeAndKinds() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        let link = clip("https://example.com", kind: .url, minutesAgo: 1)
        let code = clip("let x = 1", kind: .code, minutesAgo: 2, pinned: true)
        let text = clip("notes", minutesAgo: 3)
        try await insert([link, code, text], into: store)
        try await store.assign(clipID: link.id, toBoard: work.id)
        try await store.assign(clipID: text.id, toBoard: work.id)

        let links = LibraryBrowseQuery(scope: .all, kinds: [.url])
        #expect(try await store.libraryItems(links, offset: 0, limit: 10).map(\.id) == [link.id])
        #expect(try await store.libraryCount(links) == 1)
        let board = LibraryBrowseQuery(scope: .board(work.id))
        #expect(
            try await store.libraryItems(board, offset: 0, limit: 10).map(\.id) == [
                link.id, text.id
            ])
        #expect(try await store.libraryCount(board) == 2)
        let pinned = LibraryBrowseQuery(scope: .pinned)
        #expect(try await store.libraryItems(pinned, offset: 0, limit: 10).map(\.id) == [code.id])
        #expect(try await store.libraryCount(.init(scope: .all)) == (try await store.count()))
        let none = LibraryBrowseQuery(scope: .all, kinds: [])
        #expect(try await store.libraryItems(none, offset: 0, limit: 10).isEmpty)
        #expect(try await store.libraryCount(none) == 0)
        #expect(try await store.libraryItems(.init(scope: .all), offset: 0, limit: 0).isEmpty)
    }

    @Test("Archived and expired clips stay out of the page and the total")
    func visibility() async throws {
        let store = try makeStore()
        let kept = clip("kept", minutesAgo: 1)
        let archived = clip("archived", minutesAgo: 2)
        var expired = clip("expired", minutesAgo: 3)
        expired.isSensitive = true
        expired.expiresAt = .now.addingTimeInterval(-60)
        try await insert([kept, archived, expired], into: store)
        try await store.writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                arguments: [archived.id.uuidString])
        }
        let all = LibraryBrowseQuery(scope: .all)
        #expect(try await store.libraryItems(all, offset: 0, limit: 10).map(\.id) == [kept.id])
        #expect(try await store.libraryCount(all) == 1)
    }

    @Test("One read returns every board of every clip on the page")
    func membership() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        let brand = try await store.createPinboard(name: "Brand")
        let both = clip("both", minutesAgo: 1)
        let one = clip("one", minutesAgo: 2)
        let loose = clip("loose", minutesAgo: 3)
        try await insert([both, one, loose], into: store)
        try await store.assign(clipID: both.id, toBoard: work.id)
        try await store.assign(clipID: both.id, toBoard: brand.id)
        try await store.assign(clipID: one.id, toBoard: brand.id)

        let membership = try await store.boardIDs(forClips: [both.id, one.id, loose.id])
        #expect(membership[both.id] == [work.id, brand.id])
        #expect(membership[one.id] == [brand.id])
        #expect(membership[loose.id] == nil)
        #expect(try await store.boardIDs(forClips: []).isEmpty)
    }

    @Test("A saved filter counts what its list shows")
    func ruleCount() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        let swift = clip("swift release notes", minutesAgo: 1)
        let linkA = clip("https://swift.org", kind: .url, minutesAgo: 2)
        let linkB = clip("https://example.com", kind: .url, minutesAgo: 3)
        let phone = ClipItem(
            createdAt: .now.addingTimeInterval(-600), preview: "from the phone",
            contentHash: "phone", sourceDeviceName: "iPhone")
        try await insert([swift, linkA, linkB, phone], into: store)
        try await store.assign(clipID: linkA.id, toBoard: work.id)

        let rules: [SmartCollectionRule] = [
            SmartCollectionRule(name: "links", kinds: [.url]),
            SmartCollectionRule(name: "swift", textContains: "swift"),
            SmartCollectionRule(name: "work", boardID: work.id),
            SmartCollectionRule(name: "regex", textContains: "^https", searchMode: .regex),
            SmartCollectionRule(name: "everything"),
            SmartCollectionRule(name: "device", deviceName: "iPhone"),
            SmartCollectionRule(name: "before", createdBefore: .now.addingTimeInterval(-300))
        ]
        for rule in rules {
            let listed = try await store.items(matching: rule, limit: 100)
            #expect(try await store.count(matching: rule) == listed.count, "\(rule.name)")
        }
        #expect(
            try await store.count(matching: SmartCollectionRule(name: "no kinds", kinds: [])) == 0)
        await #expect(throws: SavedFilterError.self) {
            _ = try await store.count(matching: SmartCollectionRule(name: "gone", boardID: UUID()))
        }
    }
}
