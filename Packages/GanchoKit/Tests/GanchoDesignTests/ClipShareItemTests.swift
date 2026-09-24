import CoreTransferable
import Foundation
import GanchoKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import GanchoDesign

@Suite("Share transfer — real CoreTransferable exports")
struct ClipShareItemTests {
    private func share(_ item: ClipItem, _ store: InMemoryClipboardStore) -> ClipShareItem {
        ClipShareItem(
            id: item.id, kind: item.kind, store: store,
            isProtectedText: { $0.contains("secret") })
    }

    @Test("Export loads full text instead of the preview")
    func fullText() async throws {
        let store = InMemoryClipboardStore()
        let text = String(repeating: "synthetic text beyond the preview\n", count: 100)
        let item = ClipItem(preview: "short preview", contentHash: "share-text")
        try await store.insert(item, content: .text(text))
        let transfer = share(item, store)
        #expect(transfer.exportedContentTypes() == [.utf8PlainText])
        #expect(try await transfer.exported(as: .utf8PlainText) == Data(text.utf8))
    }

    @Test("Safe rich-text captures export their full plain text")
    func richTextBinary() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(
            kind: .text, preview: "short preview",
            contentHash: ClipItem.hash(of: "Full synthetic rich text", kind: .text))
        let rtf = Data("{\\rtf1\\ansi Full synthetic rich text}".utf8)
        try await store.insert(
            item, content: .binary(data: rtf, typeIdentifier: "public.rtf"))
        let transfer = share(item, store)

        #expect(transfer.exportedContentTypes() == [.utf8PlainText])
        #expect(
            try await transfer.exported(as: .utf8PlainText)
                == Data("Full synthetic rich text".utf8))
    }

    @Test("RTF that differs from its plain companion exports once re-classified as safe")
    func richTextBenignMismatch() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(
            kind: .text, preview: "benign",
            contentHash: ClipItem.hash(of: "benign", kind: .text))
        let rtf = Data("{\\rtf1\\ansi Formatted benign text}".utf8)
        try await store.insert(
            item, content: .binary(data: rtf, typeIdentifier: "public.rtf"))

        #expect(
            try await share(item, store).exported(as: .utf8PlainText)
                == Data("Formatted benign text".utf8))
    }

    @Test("RTF cannot export protected text that differs from its plain companion")
    func richTextMismatch() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(
            kind: .text, preview: "benign",
            contentHash: ClipItem.hash(of: "benign", kind: .text))
        let rtf = Data("{\\rtf1\\ansi synthetic secret not in plain text}".utf8)
        try await store.insert(
            item, content: .binary(data: rtf, typeIdentifier: "public.rtf"))
        let transfer = share(item, store)

        await #expect(throws: (any Error).self) {
            try await transfer.exported(as: .utf8PlainText)
        }
    }

    @Test("RTF without a classified plain companion cannot be exported")
    func richTextWithoutPlainCompanion() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(
            kind: .text, contentHash: ClipItem.hash(of: "", kind: .text))
        let rtf = Data("{\\rtf1\\ansi synthetic secret with no plain text}".utf8)
        try await store.insert(
            item, content: .binary(data: rtf, typeIdentifier: "public.rtf"))
        let transfer = share(item, store)

        await #expect(throws: (any Error).self) {
            try await transfer.exported(as: .utf8PlainText)
        }
    }

    @Test("Non-RTF binary content cannot be mislabeled as plain text")
    func nonTextBinary() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: .text)
        try await store.insert(
            item, content: .binary(data: Data([0x89, 0x50]), typeIdentifier: "public.png"))
        let transfer = share(item, store)

        await #expect(throws: (any Error).self) {
            try await transfer.exported(as: .utf8PlainText)
        }
    }

    @Test(arguments: [ClipContentKind.jwt, .creditCard, .secret, .text])
    func cannotExportProtectedKinds(kind: ClipContentKind) async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: kind, isSensitive: kind == .text)
        try await store.insert(item, content: .text("synthetic-protected-share"))
        let transfer = share(item, store)
        await #expect(throws: (any Error).self) {
            try await transfer.exported(as: .utf8PlainText)
        }
    }

    @Test("Reclassification or deletion after sharing starts rejects the lazy export")
    func changedAfterRegistration() async throws {
        let store = InMemoryClipboardStore()
        var item = ClipItem(contentHash: "share-before")
        try await store.insert(item, content: .text("synthetic-before"))
        let transfer = share(item, store)
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
        let transfer = share(item, store)
        #expect(
            try await transfer.exported(as: .utf8PlainText)
                == Data(paths.joined(separator: "\n").utf8))
    }

    @Test("Image transfer preserves PNG bytes and advertises only PNG")
    func imageBytes() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: .image)
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        try await store.insert(item, content: .binary(data: bytes, typeIdentifier: "public.png"))
        let transfer = share(item, store)
        #expect(transfer.exportedContentTypes() == [.png])
        #expect(try await transfer.exported(as: .png) == bytes)
    }

    @Test("Image export refuses a non-image content type")
    func imageTypeMismatch() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: .image)
        try await store.insert(
            item, content: .binary(data: Data([1]), typeIdentifier: "public.data"))
        let transfer = share(item, store)
        await #expect(throws: (any Error).self) { try await transfer.exported(as: .png) }
    }

    @Test("Non-PNG images are transcoded to the advertised PNG type")
    func imageTranscodesToPNG() async throws {
        let store = InMemoryClipboardStore()
        let item = ClipItem(kind: .image)
        let tiff = try Self.onePixelImage(as: .tiff)
        try await store.insert(item, content: .binary(data: tiff, typeIdentifier: "public.tiff"))

        let png = try await share(item, store).exported(as: .png)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    }

    private static func onePixelImage(as type: UTType) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
