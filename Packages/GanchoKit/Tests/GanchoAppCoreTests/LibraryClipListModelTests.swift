import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor
@Suite("Library browse requests", .timeLimit(.minutes(1)))
struct LibraryClipListModelTests {
    @MainActor private final class Source {
        var rows: [ClipItem] = (0..<250).map { ClipItem(preview: "Synthetic row \($0)") }
        var gate: SearchGate?
        var error: (any Error)?
        var requests: [(offset: Int, limit: Int)] = []

        var lastRequest: LibraryListRequest?

        func fetch(
            _ request: LibraryListRequest, offset: Int, limit: Int
        ) async throws -> [ClipItem] {
            requests.append((offset, limit))
            lastRequest = request
            let snapshot = rows
            if let gate {
                self.gate = nil
                await gate.hold()
            }
            if let error { throw error }
            return Array(snapshot.dropFirst(offset).prefix(limit))
        }
    }

    @Test("A live refresh preserves the already loaded window and reconciles removed rows")
    func reloadPreservesWindow() async {
        let source = Source()
        let model = LibraryClipListModel(fetch: source.fetch)
        await model.reload(.allClips)
        await model.loadMore()
        #expect(model.items.count == 200)
        source.rows.removeFirst()
        await model.reload(.allClips, preservingWindow: true)
        #expect(model.items == Array(source.rows.prefix(200)))
        #expect(source.requests.last?.limit == 200)
        #expect(!model.reachedEnd)
    }

    @Test("A page requested during a live refresh loads once the refresh lands")
    func pageRequestedDuringRefreshIsDeferred() async {
        let source = Source()
        let model = LibraryClipListModel(fetch: source.fetch)
        await model.reload(.allClips)
        let gate = SearchGate()
        source.gate = gate
        let refresh = Task { await model.reload(.allClips, preservingWindow: true) }
        #expect(await gate.waitUntilEntered())
        await model.loadMore()
        await gate.release()
        await refresh.value
        #expect(model.items == Array(source.rows.prefix(200)))
        #expect(!model.isLoading)
    }

    @Test("A page requested while the scope changes is dropped, not run for the new scope")
    func scopeChangeDropsDeferredPage() async {
        let source = Source()
        let model = LibraryClipListModel(fetch: source.fetch)
        await model.reload(.allClips)
        let gate = SearchGate()
        source.gate = gate
        let board = Task { await model.reload(.board(UUID())) }
        #expect(await gate.waitUntilEntered())
        await model.loadMore()
        await gate.release()
        await board.value
        #expect(model.items.count == LibraryPager.pageSize)
        #expect(source.requests.count == 2)
        #expect(!model.isLoading)
    }

    @Test("A failed refresh does not run the page requested during it")
    func failedRefreshDropsDeferredPage() async {
        let source = Source()
        let model = LibraryClipListModel(fetch: source.fetch)
        await model.reload(.allClips)
        let gate = SearchGate()
        source.gate = gate
        source.error = CocoaError(.fileReadUnknown)
        let refresh = Task { await model.reload(.allClips, preservingWindow: true) }
        #expect(await gate.waitUntilEntered())
        await model.loadMore()
        await gate.release()
        await refresh.value
        #expect(model.failure == .unavailable)
        #expect(source.requests.count == 2)
    }

    @Test("Changing scope rejects a suspended page and preserves the newer loading indicator")
    func newScopeOwnsLoading() async {
        let source = Source()
        let model = LibraryClipListModel(fetch: source.fetch)
        await model.reload(.allClips)
        let firstGate = SearchGate()
        source.gate = firstGate
        let first = Task { await model.loadMore() }
        #expect(await firstGate.waitUntilEntered())
        let secondGate = SearchGate()
        source.gate = secondGate
        source.rows = [ClipItem(isPinned: true)]
        let second = Task { await model.reload(.pinned) }
        #expect(await secondGate.waitUntilEntered())
        await firstGate.release()
        await first.value
        #expect(model.isLoading)
        #expect(model.items.isEmpty)
        await secondGate.release()
        await second.value
        #expect(model.items == source.rows)
        #expect(model.reachedEnd)
        #expect(!model.isLoading)
    }

    @Test("Read failures retain rows and can retry the failed page")
    func failureIsRecoverable() async {
        let source = Source()
        let model = LibraryClipListModel(fetch: source.fetch)
        await model.reload(.allClips)
        let initial = model.items
        source.error = CocoaError(.fileReadUnknown)
        await model.loadMore()
        #expect(model.failure == .unavailable)
        #expect(model.items == initial)
        #expect(!model.reachedEnd)
        source.error = nil
        await model.retry()
        #expect(model.items.count == 200)
        #expect(model.failure == nil)
    }

    @Test("A cancelled request cannot publish rows even if the source ignores cancellation")
    func cancelledReadCannotCommit() async {
        let source = Source()
        let model = LibraryClipListModel(fetch: source.fetch)
        let gate = SearchGate()
        source.gate = gate
        let pending = Task { await model.reload(.allClips) }
        #expect(await gate.waitUntilEntered())
        pending.cancel()
        await gate.release()
        await pending.value
        #expect(model.items.isEmpty)
        #expect(model.failure == nil)
        #expect(!model.isLoading)
    }

    @Test(
        "Filter syntax and missing-board errors are distinct from unavailable storage",
        arguments: [SavedFilterError.missingBoard, .invalidName])
    func invalidFilterIsExplained(error: SavedFilterError) async {
        let source = Source()
        source.error = error
        let model = LibraryClipListModel(fetch: source.fetch)
        await model.reload(.savedFilter(SmartCollectionRule(name: "Synthetic")))
        #expect(model.failure == .invalidFilter)
        source.error = CocoaError(.fileReadUnknown)
        await model.retry()
        #expect(model.failure == .unavailable)
    }

    @Test("Pinned browsing stops at the unpinned prefix and saved filters never paginate")
    func boundedScopes() async {
        let source = Source()
        source.rows[0].isPinned = true
        let model = LibraryClipListModel(fetch: source.fetch)
        await model.reload(.pinned)
        #expect(model.items == Array(source.rows.prefix(1)))
        #expect(model.reachedEnd)
        await model.reload(
            .savedFilter(SmartCollectionRule(name: "Synthetic", textContains: "row")))
        #expect(model.items.count == 100)
        let calls = source.requests.count
        await model.loadMore()
        #expect(source.requests.count == calls)
    }

    @Test("A search loads once, keeps the chip's kinds and orders by capture time")
    func searchLoadsOnceInOrder() async {
        let source = Source()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let older = ClipItem(createdAt: base, kind: .url, preview: "older link")
        let newer = ClipItem(
            createdAt: base.addingTimeInterval(60), kind: .url, preview: "new link")
        let pinned = ClipItem(createdAt: base.addingTimeInterval(-60), kind: .url, isPinned: true)
        let code = ClipItem(createdAt: base.addingTimeInterval(120), kind: .code, preview: "code")
        source.rows = [older, code, pinned, newer]
        let model = LibraryClipListModel(fetch: source.fetch)
        await model.reload(LibraryListRequest(scope: .allClips, text: " link ", kind: .links))
        #expect(model.items.map(\.id) == [pinned.id, newer.id, older.id])
        #expect(model.total == 3)
        #expect(model.reachedEnd)
        #expect(source.lastRequest?.searchText == "link")
        await model.reload(
            LibraryListRequest(scope: .allClips, text: "link", kind: .links, oldestFirst: true))
        #expect(model.items.map(\.id) == [pinned.id, older.id, newer.id])
        let calls = source.requests.count
        await model.loadMore()
        #expect(source.requests.count == calls, "a search never pages")
    }

    @Test("A saved filter narrows by the search words in its title and preview")
    func savedFilterSearch() async {
        let source = Source()
        source.rows = [
            ClipItem(title: "Release notes", preview: "Café menu"),
            ClipItem(preview: "Unrelated")
        ]
        let model = LibraryClipListModel(fetch: source.fetch)
        let rule = SmartCollectionRule(name: "Synthetic")
        await model.reload(LibraryListRequest(scope: .savedFilter(rule), text: "cafe release"))
        #expect(model.items.map(\.title) == ["Release notes"])
        #expect(model.total == 1)
    }

    @Test("A paged scope reports the store's total, not the loaded window")
    func pagedTotal() async {
        let source = Source()
        var counted: LibraryListRequest?
        let model = LibraryClipListModel(fetch: source.fetch) { request in
            counted = request
            return 250
        }
        let request = LibraryListRequest(scope: .allClips, kind: .code, oldestFirst: true)
        await model.reload(request)
        #expect(model.items.count == LibraryPager.pageSize)
        #expect(model.total == 250)
        #expect(counted == request)
        #expect(source.lastRequest == request)
        await model.reload(.pinned)
        #expect(model.request.kind == .code, "a scope change keeps the chip and sort")
        #expect(model.request.oldestFirst)
    }

    @Test("Each kind chip keeps exactly the kinds it names")
    func kindChips() {
        for filter in ClipKindFilter.allCases {
            for kind in ClipContentKind.allCases {
                #expect(filter.matches(kind) == (filter.kinds?.contains(kind) ?? true))
            }
        }
        #expect(ClipKindFilter.all.kinds == nil)
        #expect(ClipKindFilter.secrets.kinds == [.secret, .jwt, .creditCard])
    }
}
