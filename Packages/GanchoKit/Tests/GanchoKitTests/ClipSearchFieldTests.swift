import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Search field limits")
struct ClipSearchFieldTests {
    private func makeStore() async throws -> (GRDBClipboardStore, ClipItem) {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("search-fields-\(UUID().uuidString)")))
        try store.migrate()
        let item = ClipItem(
            title: "Roadmap title", preview: "Preview words", contentHash: "search-fields")
        try await store.insert(item, content: .text("Body sentence"))
        return (store, item)
    }

    @Test(
        "Body-only search matches the stored body and never the title or preview",
        arguments: [ClipSearchQuery.Mode.fuzzy, .exact, .regex])
    func bodyOnly(mode: ClipSearchQuery.Mode) async throws {
        let (store, item) = try await makeStore()
        func search(_ text: String) async throws -> [UUID] {
            try await store.search(ClipSearchQuery(text: text, mode: mode, bodyOnly: true))
                .map(\.id)
        }
        #expect(try await search("Body") == [item.id])
        #expect(try await search("Roadmap").isEmpty)
        #expect(try await search("Preview").isEmpty)
    }

    @Test("Body-only and metadata-only together match nothing, even with no text")
    func contradictoryLimitsMatchNothing() async throws {
        let (store, _) = try await makeStore()
        for text in ["Body", "Roadmap", ""] {
            let query = ClipSearchQuery(text: text, metadataOnly: true, bodyOnly: true)
            #expect(try await store.search(query).isEmpty, "\(text)")
        }
    }
}
