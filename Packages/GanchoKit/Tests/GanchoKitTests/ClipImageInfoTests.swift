import CoreGraphics
import Foundation
import GRDB
import ImageIO
import Testing
import UniformTypeIdentifiers

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Image size — read at capture, filled for older rows, never exported")
struct ClipImageInfoTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("image-size-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    private func png(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("The header gives the size, with EXIF orientations 5–8 swapped")
    func headerSize() throws {
        let plain = try #require(ClipImageInfo.pixelSize(of: try png(width: 12, height: 8)))
        #expect(plain.width == 12 && plain.height == 8)
        let rotated = try #require(
            ClipImageInfo.pixelSize(of: try png(width: 12, height: 8, orientation: 6)))
        #expect(rotated.width == 8 && rotated.height == 12)
        #expect(ClipImageInfo.pixelSize(of: Data("not an image".utf8)) == nil)
    }

    @Test("Untitled rows lead with the size; titled rows lead with the format")
    func rowDetail() {
        let info = ClipImageInfo(width: 1200, height: 800, typeIdentifier: "public.png")
        #expect(info.rowDetail(titled: false) == "1200 × 800 · PNG")
        #expect(info.rowDetail(titled: true) == "PNG · 1200 × 800")
        #expect(ClipImageInfo(width: 3, height: 4).rowDetail(titled: false) == "3 × 4")
    }

    @Test("A stored image carries its size and format in its metadata")
    func capturedSize() async throws {
        let store = try makeStore()
        let item = ClipItem(kind: .image, preview: "Image (1 KB)", contentHash: "img")
        try await store.insert(
            item,
            content: .binary(data: try png(width: 30, height: 20), typeIdentifier: "public.png"))
        let stored = try #require(try await store.item(id: item.id))
        #expect(
            stored.imageInfo == ClipImageInfo(width: 30, height: 20, typeIdentifier: "public.png"))
        #expect(try await store.recentForBrowse(offset: 0, limit: 5).first?.imageInfo?.width == 30)
    }

    @Test("Older rows are filled once; unreadable images are settled at 0 × 0")
    func backfill() async throws {
        let store = try makeStore()
        let good = ClipItem(kind: .image, preview: "Image", contentHash: "good")
        let bad = ClipItem(kind: .image, preview: "Image", contentHash: "bad")
        try await store.insert(
            good, content: .binary(data: try png(width: 5, height: 7), typeIdentifier: "public.png")
        )
        try await store.insert(
            bad, content: .binary(data: Data("broken".utf8), typeIdentifier: "public.png"))
        try await store.markUploaded(id: good.id, systemFields: Data([1]))
        try await store.writer.write { db in
            try db.execute(sql: "UPDATE clip SET imageWidth = NULL, imageHeight = NULL")
        }

        #expect(try await store.backfillImageSizes() == 2)
        #expect(try await store.backfillImageSizes() == 0)
        #expect(try await store.item(id: good.id)?.imageInfo?.height == 7)
        #expect(try await store.item(id: bad.id)?.imageInfo == nil)
        // Local metadata: filling it never queues an upload.
        #expect(try await store.isAwaitingUpload(id: good.id) == false)
    }
}
