import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Legacy image preview backfill")
struct LegacyPreviewBackfillTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("legacy-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("parses the byte count from both legacy shapes")
    func parses() {
        #expect(ByteSize.legacyImageByteCount("Image (734053 bytes)") == 734_053)
        #expect(
            ByteSize.legacyImageByteCount("Image (public.png, 12957256 bytes)") == 12_957_256)
        #expect(ByteSize.legacyImageByteCount("Image (717 KB)") == nil)
        #expect(ByteSize.legacyImageByteCount("just text") == nil)
    }

    @Test("rewrites a legacy image preview to a human-readable size")
    func backfills() async throws {
        let store = try makeStore()
        let item = ClipItem(kind: .image, preview: "Image (734053 bytes)", contentHash: "img1")
        try await store.insert(
            item, content: .binary(data: Data([0x1, 0x2, 0x3]), typeIdentifier: "public.png"))

        try GRDBClipboardStore.reformatLegacyImagePreviews(in: store.writer)

        let stored = try await store.items().first { $0.id == item.id }
        #expect(stored?.preview.contains("KB") == true)
        #expect(stored?.preview.contains("bytes") == false)
    }
}
