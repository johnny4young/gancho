import ClipboardCore
import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// Records what the service asked the system index to do.
private actor FakeIndex: SpotlightIndexing {
    private(set) var replaced: [[SpotlightEntry]] = []
    private(set) var removeAllCalls = 0

    func replaceAll(with entries: [SpotlightEntry]) async throws { replaced.append(entries) }
    func removeAll() async throws { removeAllCalls += 1 }
}

/// A system index whose every write fails — the runner-denied/error case.
private struct BrokenIndex: SpotlightIndexing {
    struct Failure: Error {}
    func replaceAll(with entries: [SpotlightEntry]) async throws { throw Failure() }
    func removeAll() async throws { throw Failure() }
}

/// Minimal curated-store fake: `snippets()` plus a scripted browse order.
private actor FakeCuratedStore: ClipReading, SnippetStoring {
    var snippetItems: [ClipItem] = []
    var browse: [ClipItem] = []

    init(snippets: [ClipItem], browse: [ClipItem]) {
        snippetItems = snippets
        self.browse = browse
    }

    func snippets() async throws -> [ClipItem] { snippetItems }
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] {
        Array(browse.dropFirst(offset).prefix(limit))
    }

    // ClipReading surface the service never touches.
    func items(offset: Int, limit: Int) async throws -> [ClipItem] { [] }
    func items(ids: [UUID]) async throws -> [ClipItem] { [] }
    func item(id: UUID) async throws -> ClipItem? { nil }
    func content(for id: UUID) async throws -> ClipContent? { nil }
    func count() async throws -> Int { 0 }
    func thumbnailData(for id: UUID) async throws -> Data? { nil }

    // SnippetStoring surface the service never touches.
    func promoteToSnippet(id: UUID, title: String?) async throws {}
    func demoteFromSnippet(id: UUID) async throws {}
    func snippetCount() async throws -> Int { snippetItems.count }
    func saveSnippet(title: String, text: String, language: String?) async throws -> ClipItem {
        ClipItem(preview: text)
    }
    func updateSnippet(id: UUID, title: String, text: String) async throws {}
    func setKeyword(id: UUID, keyword: String?) async throws {}
    func incrementUses(id: UUID) async throws {}
    func snippet(matchingKeyword keyword: String) async throws -> ClipItem? { nil }
}

@Suite("Library Spotlight — curated-only donation")
struct LibrarySpotlightServiceTests {
    private func clip(
        _ preview: String, title: String = "", pinned: Bool = false,
        sensitive: Bool = false, kind: ClipContentKind = .text, expires: Date? = nil
    ) -> ClipItem {
        ClipItem(
            kind: kind, title: title, preview: preview, contentHash: preview,
            isPinned: pinned, isSensitive: sensitive, expiresAt: expires)
    }

    @Test("Unsafe items never map to an entry: sensitive, expiring, masked kinds")
    func safetyBoundary() {
        #expect(LibrarySpotlightService.entry(for: clip("safe note")) != nil)
        #expect(LibrarySpotlightService.entry(for: clip("s", sensitive: true)) == nil)
        #expect(
            LibrarySpotlightService.entry(for: clip("e", expires: .now + 60)) == nil)
        #expect(LibrarySpotlightService.entry(for: clip("x", kind: .secret)) == nil)
        #expect(LibrarySpotlightService.entry(for: clip("x", kind: .jwt)) == nil)
        #expect(LibrarySpotlightService.entry(for: clip("x", kind: .creditCard)) == nil)
        #expect(LibrarySpotlightService.entry(for: clip("")) == nil, "no title, no entry")
    }

    @Test("Entries carry the title (or first preview line) — never full content")
    func entryShape() throws {
        let titled = try #require(
            LibrarySpotlightService.entry(for: clip("body text", title: "My snippet")))
        #expect(titled.title == "My snippet")

        let untitled = try #require(
            LibrarySpotlightService.entry(for: clip("first line\nsecond line")))
        #expect(untitled.title == "first line")
        #expect(untitled.summary == "first line\nsecond line")
    }

    @Test("Secret-shaped spans inside an ordinary curated clip never reach the donation")
    func entryRedactsSecretSpans() throws {
        let memo = clip(
            "deploy notes: staging key sk-live-gancho-4242424242 rotates Friday",
            title: "Deploy sk-live-gancho-4242424242", pinned: true)
        let entry = try #require(LibrarySpotlightService.entry(for: memo))
        #expect(!entry.title.contains("sk-live-gancho-4242424242"))
        #expect(!entry.summary.contains("sk-live-gancho-4242424242"))
        #expect(entry.summary.contains("[redacted]"))
    }

    @Test("Reconcile donates snippets plus the pinned browse prefix, de-duplicated")
    func reconcileComposesTheCuratedSet() async {
        var snippet = clip("deploy checklist", title: "Deploy")
        let pinnedSnippet = clip("shared", title: "Both", pinned: true)
        let pinnedOnly = clip("pinned note", pinned: true)
        let rawHistory = clip("raw history row")
        snippet.uses = 3

        let store = FakeCuratedStore(
            snippets: [snippet, pinnedSnippet],
            browse: [pinnedSnippet, pinnedOnly, rawHistory, clip("more raw")])
        let index = FakeIndex()
        await LibrarySpotlightService(index: index).reconcile(store: store, enabled: true)

        let donated = await index.replaced
        #expect(donated.count == 1)
        let ids = Set(donated[0].map(\.id))
        #expect(ids == Set([snippet.id, pinnedSnippet.id, pinnedOnly.id]))
        #expect(
            !donated[0].contains { $0.id == rawHistory.id },
            "raw history must never be donated")
    }

    @Test("A sensitive pinned clip is dropped at the mapping layer")
    func sensitivePinnedNeverDonated() async {
        let sensitivePin = clip("secret-ish", pinned: true, sensitive: true)
        let store = FakeCuratedStore(snippets: [], browse: [sensitivePin, clip("raw")])
        let index = FakeIndex()
        await LibrarySpotlightService(index: index).reconcile(store: store, enabled: true)
        #expect(await index.replaced == [[]])
    }

    @Test("Disabling the toggle wipes the domain instead of donating")
    func disabledWipes() async {
        let store = FakeCuratedStore(snippets: [clip("s", title: "T")], browse: [])
        let index = FakeIndex()
        let landed = await LibrarySpotlightService(index: index)
            .reconcile(store: store, enabled: false)
        #expect(landed)
        #expect(await index.removeAllCalls == 1)
        #expect(await index.replaced.isEmpty, "nothing may be donated while disabled")
    }

    @Test("A failed system-index write is reported, not swallowed")
    func indexFailureSurfaces() async {
        let store = FakeCuratedStore(snippets: [clip("s", title: "T")], browse: [])
        let broken = BrokenIndex()
        let service = LibrarySpotlightService(index: broken)
        #expect(await service.reconcile(store: store, enabled: true) == false)
        #expect(await service.reconcile(store: store, enabled: false) == false)
    }

    @Test("Pinned collection pages across the boundary and stops at the first unpinned row")
    func pinnedPrefixPagination() async {
        // More pins than one page (50) proves the page walk; the unpinned tail
        // proves the stop condition.
        let pins = (0..<60).map { clip("pin \($0)", pinned: true) }
        let store = FakeCuratedStore(snippets: [], browse: pins + [clip("raw")])
        let index = FakeIndex()
        await LibrarySpotlightService(index: index).reconcile(store: store, enabled: true)
        let donated = await index.replaced
        #expect(donated.first?.count == 60)
    }
}
