import CoreTransferable
import Foundation
import GanchoKit
import Testing
import UniformTypeIdentifiers

@testable import GanchoDesign

@Suite("Share transfer — real CoreTransferable exports")
struct ClipShareItemTests {
    @Test("Export loads full text instead of the preview")
    func fullText() async throws {
        let store = InMemoryClipboardStore()
        let text = String(repeating: "synthetic text beyond the preview\n", count: 100)
        let item = ClipItem(preview: "short preview", contentHash: "share-text")
        try await store.insert(item, content: .text(text))
        let transfer = ClipShareItem(id: item.id, kind: item.kind, store: store)
        #expect(transfer.exportedContentTypes() == [.utf8PlainText])
        #expect(try await transfer.exported(as: .utf8PlainText) == Data(text.utf8))
    }

    @Test("Safe rich-text captures export their full plain text")
    func richTextBinary() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: .text, preview: "short preview")
        let rtf = Data("{\\rtf1\\ansi Full synthetic rich text}".utf8)
        try await store.insert(
            item, content: .binary(data: rtf, typeIdentifier: "public.rtf"))
        let transfer = ClipShareItem(id: item.id, kind: item.kind, store: store)

        #expect(transfer.exportedContentTypes() == [.utf8PlainText])
        #expect(
            try await transfer.exported(as: .utf8PlainText)
                == Data("Full synthetic rich text".utf8))
    }

    @Test("Non-RTF binary content cannot be mislabeled as plain text")
    func nonTextBinary() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: .text)
        try await store.insert(
            item, content: .binary(data: Data([0x89, 0x50]), typeIdentifier: "public.png"))
        let transfer = ClipShareItem(id: item.id, kind: item.kind, store: store)

        await #expect(throws: (any Error).self) {
            try await transfer.exported(as: .utf8PlainText)
        }
    }

    @Test(arguments: [ClipContentKind.jwt, .creditCard, .secret, .text])
    func cannotExportProtectedKinds(kind: ClipContentKind) async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: kind, isSensitive: kind == .text)
        try await store.insert(item, content: .text("synthetic-protected-share"))
        let transfer = ClipShareItem(id: item.id, kind: kind, store: store)
        await #expect(throws: (any Error).self) {
            try await transfer.exported(as: .utf8PlainText)
        }
    }

    @Test("Reclassification or deletion after sharing starts rejects the lazy export")
    func changedAfterRegistration() async throws {
        let store = InMemoryClipboardStore()
        var item = ClipItem(contentHash: "share-before")
        try await store.insert(item, content: .text("synthetic-before"))
        let transfer = ClipShareItem(id: item.id, kind: item.kind, store: store)
        try await store.delete(id: item.id)
        await #expect(throws: (any Error).self) { try await transfer.exported(as: .utf8PlainText) }
        item.kind = .secret
        try await store.insert(item, content: .text("synthetic-after"))
        await #expect(throws: (any Error).self) { try await transfer.exported(as: .utf8PlainText) }
    }

    @Test("File references share their full path list, never a preview")
    func fileReferences() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: .fileReference, preview: "two files")
        let paths = ["/synthetic/one", "/synthetic/two"]
        try await store.insert(item, content: .fileReferences(paths))
        let transfer = ClipShareItem(id: item.id, kind: item.kind, store: store)
        #expect(
            try await transfer.exported(as: .utf8PlainText)
                == Data(paths.joined(separator: "\n").utf8))
    }

    @Test("Image transfer preserves original binary bytes and advertises only image")
    func imageBytes() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: .image)
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        try await store.insert(item, content: .binary(data: bytes, typeIdentifier: "public.png"))
        let transfer = ClipShareItem(id: item.id, kind: item.kind, store: store)
        #expect(transfer.exportedContentTypes() == [.image])
        #expect(try await transfer.exported(as: .image) == bytes)
    }

    @Test("Image export refuses a non-image content type")
    func imageTypeMismatch() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: .image)
        try await store.insert(
            item, content: .binary(data: Data([1]), typeIdentifier: "public.data"))
        let transfer = ClipShareItem(id: item.id, kind: item.kind, store: store)
        await #expect(throws: (any Error).self) { try await transfer.exported(as: .image) }
    }
}
