import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import GanchoAppCore

@Suite("Notch shelf image edits")
struct ImageEditsTests {
    /// A solid image, optionally rotated by EXIF orientation 6 and geotagged.
    private func image(
        width: Int, height: Int, type: String = "public.jpeg", orientation: Int? = nil,
        location: Bool = false
    ) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = try #require(context.makeImage())
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        if location {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 4.711, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 74.072, kCGImagePropertyGPSLongitudeRef: "W"
            ]
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: "2026:11:01 10:00:00"
            ]
        }
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test("Resize caps the long edge, keeps the format and bakes the orientation in")
    func resize() throws {
        let original = try image(width: 2000, height: 1000, orientation: 6)
        guard case .edited(let data, let type) = ImageEdits.resize(original) else {
            Issue.record("expected an edit")
            return
        }
        #expect(type == "public.jpeg")
        let resized = try properties(data)
        // Orientation 6 turns the 2000×1000 pixels upright: 640×1280.
        #expect(resized[kCGImagePropertyPixelWidth] as? Int == ImageEdits.resizedLongEdge / 2)
        #expect(resized[kCGImagePropertyPixelHeight] as? Int == ImageEdits.resizedLongEdge)
        #expect((resized[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test("Resize never enlarges, and refuses what isn't an image")
    func resizeLimits() throws {
        let edge = ImageEdits.resizedLongEdge
        #expect(ImageEdits.resize(try image(width: edge, height: 600)) == .unchanged)
        #expect(
            ImageEdits.resize(try image(width: 300, height: 200, type: "public.png")) == .unchanged)
        #expect(ImageEdits.resize(Data("not an image".utf8)) == .failed)
        guard
            case .edited(_, let type) = ImageEdits.resize(
                try image(width: edge + 1, height: 10, type: "public.png"))
        else {
            Issue.record("expected an edit")
            return
        }
        #expect(type == "public.png")
    }

    @Test("Strip location removes GPS and keeps the orientation, EXIF and pixels")
    func stripLocation() throws {
        let original = try image(width: 400, height: 300, orientation: 6, location: true)
        #expect(ImageEdits.hasLocation(original))
        guard case .edited(let data, let type) = ImageEdits.stripLocation(original) else {
            Issue.record("expected an edit")
            return
        }
        #expect(type == "public.jpeg")
        #expect(!ImageEdits.hasLocation(data))
        let stripped = try properties(data)
        #expect(stripped[kCGImagePropertyOrientation] as? Int == 6)
        let exif = stripped[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:11:01 10:00:00")
        #expect(stripped[kCGImagePropertyPixelWidth] as? Int == 400)
        #expect(stripped[kCGImagePropertyPixelHeight] as? Int == 300)
    }

    @Test("Nothing to strip leaves the image alone")
    func stripNothing() throws {
        #expect(ImageEdits.stripLocation(try image(width: 40, height: 30)) == .unchanged)
        #expect(ImageEdits.stripLocation(Data("not an image".utf8)) == .failed)
    }
}
