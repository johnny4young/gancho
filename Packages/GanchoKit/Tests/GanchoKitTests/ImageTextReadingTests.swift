import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Explicit OCR read boundary")
struct ImageTextReadingTests {
    @Test("Reads cached OCR without changing the image or its sync revision")
    func cached() async throws {
        let store = try makeStore()
        let item = ClipItem(kind: .image, contentHash: "ocr-image")
        _ = try await store.insert(
            item, content: .binary(data: Data([1, 2]), typeIdentifier: "public.png"))
        #expect(try await store.imageTextInput(id: item.id, now: .now) == .image(Data([1, 2])))
        try await store.attachExtractedText(id: item.id, text: "already indexed")
        let before = try await store.item(id: item.id)
        #expect(
            try await store.imageTextInput(id: item.id, now: .now) == .cached("already indexed"))
        #expect(try await store.item(id: item.id) == before)
        #expect(
            try await store.content(for: item.id)
                == .binary(data: Data([1, 2]), typeIdentifier: "public.png"))
    }

    @Test("Rejects sensitive, expired, nonimage, archived and missing rows")
    func vetoes() async throws {
        let store = try makeStore()
        for index in 0..<4 {
            let item = ClipItem(
                kind: index == 2 ? .text : .image, contentHash: "veto-\(index)",
                isSensitive: index == 0, expiresAt: index == 1 ? .distantPast : nil)
            _ = try await store.insert(item, content: .text("must not escape"))
            if index == 3 {
                try await store.writer.write { db in
                    try db.execute(
                        sql: "UPDATE clip SET isArchived = 1 WHERE id = ?",
                        arguments: [item.id.uuidString])
                }
            }
            #expect(try await !store.permitsImageText(id: item.id, now: .now))
            #expect(try await store.imageTextInput(id: item.id, now: .now) == nil)
        }
        #expect(try await store.imageTextInput(id: UUID(), now: .now) == nil)
    }

    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString)))
        try store.migrate()
        return store
    }
}
