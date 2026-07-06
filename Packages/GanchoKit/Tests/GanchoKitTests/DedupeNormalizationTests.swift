import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("ContentNormalizer — canonical text")
struct ContentNormalizerTests {
    @Test(
        "Tracking parameters are stripped, functional ones survive",
        arguments: [
            (
                "https://example.com/article?utm_source=x&utm_campaign=y&id=42",
                "https://example.com/article?id=42"
            ),
            (
                "https://shop.example.com/item?fbclid=abc123",
                "https://shop.example.com/item"
            ),
            (
                "https://example.com/path?gclid=1&page=2&msclkid=9",
                "https://example.com/path?page=2"
            ),
            // No query → untouched.
            ("https://example.com/plain", "https://example.com/plain"),
            // Non-URL text → untouched, even if it smells like one.
            ("not a url utm_source=x", "not a url utm_source=x"),
        ])
    func stripsTracking(input: String, expected: String) {
        #expect(ContentNormalizer.normalizeURL(input) == expected)
    }

    @Test("Canonical text only rewrites URLs")
    func canonicalOnlyTouchesURLs() {
        let prose = "read https://example.com?utm_source=x later"
        #expect(ContentNormalizer.canonicalText(prose, kind: .text) == prose)
        #expect(
            ContentNormalizer.canonicalText(
                " https://example.com/a?utm_source=n ", kind: .url)
                == "https://example.com/a")
    }
}

@Suite("Store dedupe — move to top, device-aware")
struct StoreDedupeTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("dedupe-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Copying the same text 5 times yields 1 item with fresh lastUsedAt")
    func fiveCopiesOneItem() async throws {
        let store = try makeStore()
        let hash = ClipItem.hash(of: "same text", kind: .text)

        var lastReturned: ClipItem?
        for _ in 0..<5 {
            lastReturned = try await store.insert(
                ClipItem(preview: "same text", contentHash: hash),
                content: .text("same text"))
        }

        #expect(try await store.count() == 1)
        #expect(lastReturned?.lastUsedAt != nil, "re-copy must refresh lastUsedAt")
    }

    @Test("Re-copy floats the item back to the top of the list")
    func recopyMovesToTop() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let first = ClipItem(
            createdAt: base, lastUsedAt: base, preview: "older", contentHash: "h-old")
        let second = ClipItem(
            createdAt: base.addingTimeInterval(60), lastUsedAt: base.addingTimeInterval(60),
            preview: "newer", contentHash: "h-new")
        try await store.insert(first, content: .text("older"))
        try await store.insert(second, content: .text("newer"))

        // Re-copy the OLDER content.
        try await store.insert(
            ClipItem(preview: "older", contentHash: "h-old"), content: .text("older"))

        let items = try await store.items()
        #expect(items.map(\.preview) == ["older", "newer"])
        #expect(try await store.count() == 2)
    }

    @Test("A freshly captured clip sorts above an older, previously-used clip")
    func freshClipBeatsUsedClip() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // An older clip that was used once (non-nil lastUsedAt, in the past).
        let used = ClipItem(
            createdAt: base, lastUsedAt: base.addingTimeInterval(60),
            preview: "used", contentHash: "h-used")
        // A brand-new clip captured later, never re-used (lastUsedAt nil).
        let fresh = ClipItem(
            createdAt: base.addingTimeInterval(120), lastUsedAt: nil,
            preview: "fresh", contentHash: "h-fresh")
        try await store.insert(used, content: .text("used"))
        try await store.insert(fresh, content: .text("fresh"))

        // Recency coalesces lastUsedAt with createdAt: the fresh clip's createdAt
        // beats the used clip's older lastUsedAt, so it sorts first. Ordering by
        // lastUsedAt alone (NULLs last) would wrongly sink the new clip below it.
        #expect(try await store.items().map(\.preview) == ["fresh", "used"])
    }

    @Test("Same content from another device stays a separate row (no sync loops)")
    func deviceScopedDedupe() async throws {
        let store = try makeStore()
        let hash = ClipItem.hash(of: "shared", kind: .text)

        try await store.insert(
            ClipItem(preview: "shared", contentHash: hash, sourceDeviceName: "Mac"),
            content: .text("shared"))
        try await store.insert(
            ClipItem(preview: "shared", contentHash: hash, sourceDeviceName: "iPhone"),
            content: .text("shared"))

        #expect(try await store.count() == 2, "cross-device rows must not merge")
    }

    @Test("Sheets-style rich noise dedupes via the plain-text hash")
    func richNoiseDedupes() async throws {
        let store = try makeStore()
        // Two copies of the same cell: the rich payload differs (fresh UUID
        // each time, as Google Sheets does) but the plain text is identical —
        // the pipeline hashes plain text, so they collapse.
        let plain = "Q3 revenue 1,284"
        let hash = ClipItem.hash(of: plain, kind: .text)
        try await store.insert(
            ClipItem(preview: plain, contentHash: hash), content: .text(plain))
        try await store.insert(
            ClipItem(preview: plain, contentHash: hash), content: .text(plain))

        #expect(try await store.count() == 1)
    }
}
