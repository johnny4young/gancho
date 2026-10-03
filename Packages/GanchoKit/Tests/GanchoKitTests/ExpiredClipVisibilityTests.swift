import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Expired clips stay hidden until retention purges them")
struct ExpiredClipVisibilityTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("expired-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Lists, search, count and content skip a row past its expiry")
    func expiredRowIsHidden() async throws {
        let store = try makeStore()
        let live = ClipItem(preview: "shared live", contentHash: "live")
        let expired = ClipItem(
            preview: "shared expired", contentHash: "expired",
            expiresAt: Date.now.addingTimeInterval(-1))
        try await store.insert(live, content: .text("shared live"))
        try await store.insert(expired, content: .text("shared expired"))

        #expect(try await store.items(offset: 0, limit: 10).map(\.id) == [live.id])
        #expect(try await store.recentForBrowse(offset: 0, limit: 10).map(\.id) == [live.id])
        #expect(try await store.items(ids: [live.id, expired.id]).map(\.id) == [live.id])
        #expect(try await store.count() == 1)
        #expect(try await store.search(ClipSearchQuery(text: "shared")).map(\.id) == [live.id])
        #expect(
            try await store.search(ClipSearchQuery(text: "shar.d", mode: .regex)).map(\.id)
                == [live.id])
        #expect(try await store.content(for: expired.id) == nil)
        #expect(try await store.content(for: live.id) == .text("shared live"))
    }

    @Test("A pinned non-sensitive row retention keeps stays visible past its date")
    func retainedRowStaysVisible() async throws {
        let store = try makeStore()
        let pinned = ClipItem(
            preview: "kept", contentHash: "kept", isPinned: true,
            expiresAt: Date.now.addingTimeInterval(-1))
        try await store.insert(pinned, content: .text("kept"))

        #expect(try await store.items(offset: 0, limit: 10).map(\.id) == [pinned.id])
        #expect(try await store.content(for: pinned.id) == .text("kept"))
    }

    @Test("Metadata-only search matches title and preview but not the body")
    func metadataOnlySearch() async throws {
        let store = try makeStore()
        let item = ClipItem(title: "Invoice", preview: "Invoice", contentHash: "m")
        try await store.insert(item, content: .text("Invoice body with hidden-term"))

        let body = ClipSearchQuery(text: "hidden", metadataOnly: true)
        let title = ClipSearchQuery(text: "invoice", metadataOnly: true)
        let exact = ClipSearchQuery(text: "hidden-term", mode: .exact, metadataOnly: true)

        #expect(try await store.search(body).isEmpty)
        #expect(try await store.search(exact).isEmpty)
        #expect(try await store.search(title).map(\.id) == [item.id])
        #expect(try await store.search(ClipSearchQuery(text: "hidden")).map(\.id) == [item.id])
    }
}
