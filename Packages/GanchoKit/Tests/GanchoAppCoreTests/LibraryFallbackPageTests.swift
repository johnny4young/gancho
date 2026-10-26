import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Library in-memory fallback pages")
struct LibraryFallbackPageTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Newest first, like the in-memory store: `rows[0]` is the latest capture.
    private func rows(
        _ count: Int, kind: ClipContentKind = .text, preview: String = "Synthetic row",
        olderThan offset: Int = 0
    ) -> [ClipItem] {
        (0..<count).map {
            ClipItem(
                createdAt: Self.start.addingTimeInterval(-Double(offset + $0)), kind: kind,
                preview: "\(preview) \(offset + $0)")
        }
    }

    private func page(
        _ request: LibraryListRequest, _ snapshot: [ClipItem], offset: Int = 0, limit: Int = 100
    ) async -> [ClipItem] {
        await request.fallbackPage(offset: offset, limit: limit) { snapshot }
    }

    @Test("A kind filter reaches matches behind the first raw page")
    func kindFilterSeesOlderRows() async {
        let snapshot = rows(100) + rows(30, kind: .url, olderThan: 100)
        let request = LibraryListRequest(scope: .allClips, kind: .links)
        let first = await page(request, snapshot, limit: 20)
        let second = await page(request, snapshot, offset: 20, limit: 20)
        #expect(first.map(\.id) == Array(snapshot[100..<120]).map(\.id))
        #expect(second.map(\.id) == Array(snapshot[120..<130]).map(\.id))
    }

    @Test("Pinned scope keeps an old pin and drops unpinned search hits")
    func pinnedScope() async {
        var snapshot = rows(150, preview: "Invoice")
        snapshot[140].isPinned = true
        let browse = await page(LibraryListRequest(scope: .pinned), snapshot)
        let search = await page(LibraryListRequest(scope: .pinned, text: "invoice"), snapshot)
        #expect(browse.map(\.id) == [snapshot[140].id])
        #expect(search.map(\.id) == [snapshot[140].id])
    }

    @Test("Search matches every word, ignoring case and accents, then pages")
    func searchPages() async {
        let snapshot =
            rows(3, preview: "Café menu") + rows(2, preview: "Tea", olderThan: 3)
            + rows(2, preview: "cafe MENU", olderThan: 5)
        let request = LibraryListRequest(scope: .allClips, text: " cafe menu ")
        let all = await page(request, snapshot)
        let tail = await page(request, snapshot, offset: 3, limit: 10)
        #expect(all.count == 5)
        #expect(tail.map(\.id) == Array(snapshot[5..<7]).map(\.id))
    }

    @Test("Pins lead, then capture time in the requested direction")
    func ordering() async {
        var snapshot = rows(4)
        snapshot[3].isPinned = true
        let newest = await page(LibraryListRequest(scope: .allClips), snapshot)
        let oldest = await page(LibraryListRequest(scope: .allClips, oldestFirst: true), snapshot)
        #expect(newest.map(\.id) == [3, 0, 1, 2].map { snapshot[$0].id })
        #expect(oldest.map(\.id) == [3, 2, 1, 0].map { snapshot[$0].id })
    }

    @Test(
        "Durable-only scopes and empty pages read nothing",
        arguments: [
            (LibraryListRequest(scope: .board(UUID())), 50),
            (LibraryListRequest(scope: .savedFilter(SmartCollectionRule(name: "Rule"))), 50),
            (LibraryListRequest(scope: .allClips), 0)
        ])
    func skipsSnapshot(request: LibraryListRequest, limit: Int) async {
        var reads = 0
        let result = await request.fallbackPage(offset: 0, limit: limit) {
            reads += 1
            return rows(10)
        }
        #expect(result.isEmpty)
        #expect(reads == 0)
    }
}
