import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// A mutable store stand-in with the real offset semantics: every fetch is a
/// slice of the CURRENT rows, so mutations between two requests shift what
/// an offset means — exactly the situation the pager reconciles.
private final class ShiftingRows: @unchecked Sendable {
    var rows: [ClipItem]
    var fetches: [(offset: Int, limit: Int)] = []
    var failNext: (any Error)?

    init(_ rows: [ClipItem]) { self.rows = rows }

    func fetch(_ offset: Int, _ limit: Int) async throws -> [ClipItem] {
        fetches.append((offset, limit))
        if let error = failNext {
            failNext = nil
            throw error
        }
        return Array(rows.dropFirst(offset).prefix(limit))
    }
}

private func clip(_ n: Int, pinned: Bool = false) -> ClipItem {
    ClipItem(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!,
        createdAt: .distantPast, updatedAt: .distantPast, preview: "row \(n)", isPinned: pinned)
}

private func ids(_ outcome: LibraryPager.Outcome) -> [Int]? {
    guard case .loaded(let items, _) = outcome else { return nil }
    return items.map { Int($0.id.uuidString.suffix(12))! }
}

@Suite struct LibraryPagerTests {
    @Test("A first page loads from zero and short pages mean EOF")
    func firstPage() async {
        let store = ShiftingRows((1...7).map { clip($0) })
        let outcome = await LibraryPager.nextPage(loaded: [], pageSize: 10, fetch: store.fetch)
        #expect(outcome == .loaded(store.rows, reachedEnd: true))
        #expect(store.fetches.map(\.offset) == [0])
    }

    @Test("A full page keeps the scope open and the next page appends after the anchor")
    func steadyState() async {
        let store = ShiftingRows((1...25).map { clip($0) })
        let firstPage = await LibraryPager.nextPage(loaded: [], pageSize: 10, fetch: store.fetch)
        guard case .loaded(let first, let end) = firstPage else {
            Issue.record("first page failed")
            return
        }
        #expect(!end)
        let second = await LibraryPager.nextPage(loaded: first, pageSize: 10, fetch: store.fetch)
        #expect(ids(second) == Array(1...20))
        // Overlap rows re-read from before the tail, then one page.
        #expect(store.fetches.last?.offset == 10 - LibraryPager.overlap)
        let third = await LibraryPager.nextPage(
            loaded: (1...20).map { clip($0) }, pageSize: 10, fetch: store.fetch)
        #expect(third == .loaded(store.rows, reachedEnd: true))
    }

    @Test("A cancelled page leaves the list and the EOF flag alone, and a retry succeeds")
    func cancelledPageIsNotEOF() async {
        let store = ShiftingRows((1...5).map { clip($0) })
        let loaded = (1...3).map { clip($0) }
        store.failNext = CancellationError()
        let failed = await LibraryPager.nextPage(loaded: loaded, pageSize: 10, fetch: store.fetch)
        #expect(failed == .failed)
        let retry = await LibraryPager.nextPage(loaded: loaded, pageSize: 10, fetch: store.fetch)
        #expect(retry == .loaded(store.rows, reachedEnd: true))
    }

    @Test("A read error is reported as a failure, never as an empty final page")
    func readErrorIsNotEOF() async {
        struct Boom: Error {}
        let store = ShiftingRows((1...30).map { clip($0) })
        store.failNext = Boom()
        let outcome = await LibraryPager.nextPage(
            loaded: (1...10).map { clip($0) }, pageSize: 10, fetch: store.fetch)
        #expect(outcome == .failed)
    }

    @Test("A capture inserted above the loaded rows neither skips nor duplicates")
    func insertBetweenPages() async {
        let store = ShiftingRows((1...25).map { clip($0) })
        let loaded = Array(store.rows.prefix(10))
        store.rows.insert(clip(100), at: 0)
        let outcome = await LibraryPager.nextPage(loaded: loaded, pageSize: 10, fetch: store.fetch)
        #expect(ids(outcome) == [100] + Array(1...19))
        if case .loaded(_, let end) = outcome { #expect(!end) }
    }

    @Test("Retention removing a loaded row does not skip the row that slid up")
    func deleteBetweenPages() async {
        let store = ShiftingRows((1...25).map { clip($0) })
        let loaded = Array(store.rows.prefix(10))
        store.rows.removeAll { $0.id == clip(3).id }
        let outcome = await LibraryPager.nextPage(loaded: loaded, pageSize: 10, fetch: store.fetch)
        // Naive `offset = loaded.count` would have skipped row 11.
        #expect(ids(outcome) == [1, 2] + Array(4...21))
    }

    @Test("A delete beyond the loaded rows is invisible and paging just continues")
    func deleteBeyondLoadedRows() async {
        let store = ShiftingRows((1...25).map { clip($0) })
        let loaded = Array(store.rows.prefix(10))
        store.rows.removeAll { $0.id == clip(24).id }
        let outcome = await LibraryPager.nextPage(loaded: loaded, pageSize: 10, fetch: store.fetch)
        #expect(ids(outcome) == Array(1...20))
        #expect(store.fetches.count == 1, "no snapshot re-read when the anchor still matches")
    }

    @Test("A shifted window re-reads one snapshot and marks EOF only when it is short")
    func shiftedWindowEOF() async {
        let store = ShiftingRows((1...12).map { clip($0) })
        let loaded = Array(store.rows.prefix(10))
        store.rows.removeFirst()
        let outcome = await LibraryPager.nextPage(loaded: loaded, pageSize: 10, fetch: store.fetch)
        #expect(outcome == .loaded(store.rows, reachedEnd: true))
        #expect(store.fetches.count == 2)
    }

    @Test("A prefix scope stops at the first row outside it and reports EOF")
    func pinnedPrefix() async {
        let store = ShiftingRows(
            (1...3).map { clip($0, pinned: true) } + (4...30).map { clip($0) })
        let outcome = await LibraryPager.nextPage(
            loaded: [], pageSize: 10, stopAt: { !$0.isPinned }, fetch: store.fetch)
        #expect(outcome == .loaded(Array(store.rows.prefix(3)), reachedEnd: true))
    }

    @Test("Unpinning a loaded row between pages shrinks the prefix instead of duplicating")
    func unpinBetweenPages() async {
        let store = ShiftingRows(
            (1...12).map { clip($0, pinned: true) } + (13...30).map { clip($0) })
        let loaded = Array(store.rows.prefix(10))
        // Row 2 loses its pin and sinks below the pinned prefix.
        store.rows.remove(at: 1)
        store.rows.insert(clip(2), at: 11)
        let outcome = await LibraryPager.nextPage(
            loaded: loaded, pageSize: 10, stopAt: { !$0.isPinned }, fetch: store.fetch)
        #expect(ids(outcome) == [1] + Array(3...12))
        if case .loaded(_, let end) = outcome { #expect(end) }
    }
}
