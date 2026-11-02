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

    @Test("Preferring the image skips stored text, and the vetoes still apply")
    func preferringImage() async throws {
        let store = try makeStore()
        let item = ClipItem(kind: .image, contentHash: "ocr-fresh")
        _ = try await store.insert(
            item, content: .binary(data: Data([5, 6]), typeIdentifier: "public.png"))
        try await store.attachExtractedText(id: item.id, text: "already indexed")
        #expect(
            try await store.imageTextInput(id: item.id, now: .now, preferringImage: true)
                == .image(Data([5, 6])))
        let secret = ClipItem(kind: .image, contentHash: "ocr-fresh-secret", isSensitive: true)
        _ = try await store.insert(
            secret, content: .binary(data: Data([7]), typeIdentifier: "public.png"))
        #expect(
            try await store.imageTextInput(id: secret.id, now: .now, preferringImage: true) == nil)
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

    @Test("Attaching OCR text queues no upload and keeps the sync revision")
    func attachIsDeviceLocal() async throws {
        let store = try makeStore()
        let item = ClipItem(kind: .image, contentHash: "ocr-local")
        _ = try await store.insert(
            item, content: .binary(data: Data([3, 4]), typeIdentifier: "public.png"))
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        let before = try await store.item(id: item.id)

        try await store.attachExtractedText(id: item.id, text: "indexed locally")

        #expect(try await store.pendingUploadIDs().isEmpty)
        #expect(try await store.item(id: item.id)?.updatedAt == before?.updatedAt)
        #expect(
            try await store.imageTextInput(id: item.id, now: .now) == .cached("indexed locally"))
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
