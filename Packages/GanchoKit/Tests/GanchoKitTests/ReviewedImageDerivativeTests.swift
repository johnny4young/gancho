import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import GanchoKit

/// Synthetic images only; every fixture is drawn in memory.
enum ReviewedImageFixture {
    static func image(
        width: Int, height: Int, noise: Bool = false
    ) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if noise, let pixels = context.data?.assumingMemoryBound(to: UInt32.self) {
            var state: UInt32 = 0x9E37_79B9
            for index in 0..<(context.bytesPerRow / 4 * height) {
                state = state &* 1_664_525 &+ 1_013_904_223
                pixels[index] = state | 0xFF00_0000
            }
        } else {
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return context.makeImage()!
    }

    static func encode(
        _ image: CGImage, as type: UTType = .png, properties: [CFString: Any] = [:]
    ) -> Data {
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func properties(of data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }
}

@Suite("Reviewed image derivative")
struct ReviewedImageDerivativeTests {
    private typealias Fixture = ReviewedImageFixture

    @Test("Location, comments and camera metadata never survive the derivative")
    func stripsMetadata() throws {
        let source = Fixture.encode(
            Fixture.image(width: 320, height: 200), as: .jpeg,
            properties: [
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 4.711, kCGImagePropertyGPSLatitudeRef: "N"
                ],
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifUserComment: "synthetic-private-comment"
                ],
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Synthetic Camera"]
            ])
        #expect(Fixture.properties(of: source)[kCGImagePropertyGPSDictionary] != nil)

        let derivative = try ReviewedImageDerivative.make(from: source)
        let properties = Fixture.properties(of: derivative.data)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(
            (properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[
                kCGImagePropertyExifUserComment] == nil)
        #expect(properties[kCGImagePropertyTIFFDictionary] == nil)
        #expect(!derivative.data.contains(Data("synthetic-private-comment".utf8)))
        #expect(!derivative.data.contains(Data("Synthetic Camera".utf8)))
    }

    @Test("A wide image is scaled so its longest side is the maximum")
    func scalesDown() throws {
        let derivative = try ReviewedImageDerivative.make(
            from: Fixture.encode(Fixture.image(width: 4_000, height: 1_000)))
        #expect(derivative.width == ReviewedImageDerivative.maximumPixelSize)
        #expect(derivative.height == ReviewedImageDerivative.maximumPixelSize / 4)
        #expect(derivative.mimeType == "image/png")
    }

    @Test("A small image keeps its size")
    func keepsSmallImages() throws {
        let derivative = try ReviewedImageDerivative.make(
            from: Fixture.encode(Fixture.image(width: 320, height: 120)))
        #expect(derivative.width == 320)
        #expect(derivative.height == 120)
    }

    @Test("EXIF orientation is applied to the pixels instead of being carried along")
    func appliesOrientation() throws {
        let source = Fixture.encode(
            Fixture.image(width: 200, height: 100), as: .jpeg,
            properties: [kCGImagePropertyOrientation: 6])
        let derivative = try ReviewedImageDerivative.make(from: source)
        #expect(derivative.width == 100)
        #expect(derivative.height == 200)
        #expect(Fixture.properties(of: derivative.data)[kCGImagePropertyOrientation] == nil)
    }

    @Test("A PNG too big to send falls back to JPEG within the byte limit")
    func fallsBackToJPEG() throws {
        let source = Fixture.encode(Fixture.image(width: 1_200, height: 1_200, noise: true))
        #expect(source.count > ReviewedImageDerivative.maximumEncodedBytes)
        let derivative = try ReviewedImageDerivative.make(from: source)
        #expect(derivative.mimeType == "image/jpeg")
        #expect(derivative.data.count <= ReviewedImageDerivative.maximumEncodedBytes)
    }

    @Test("A header that declares too many pixels is refused before decoding")
    func refusesHugeHeaders() throws {
        let side = 8_000
        #expect(side * side > ReviewedImageDerivative.maximumSourcePixels)
        let forged = try JPEGHeader.declaring(
            width: side, height: side,
            in: Fixture.encode(Fixture.image(width: 16, height: 16), as: .jpeg))
        let declared = Fixture.properties(of: forged)
        #expect(declared[kCGImagePropertyPixelWidth] as? Int == side, "ImageIO reads the header")
        #expect(throws: ReviewedImageDerivative.Failure.tooManyPixels) {
            try ReviewedImageDerivative.make(from: forged)
        }
    }

    @Test("Bytes that are not an image are unreadable")
    func refusesNonImages() {
        #expect(throws: ReviewedImageDerivative.Failure.unreadable) {
            try ReviewedImageDerivative.make(from: Data("not an image".utf8))
        }
    }
}

/// Rewrites the dimensions in a JPEG's start-of-frame segment, leaving the
/// compressed data for a 16-pixel image: a cheap stand-in for a huge file.
enum JPEGHeader {
    struct Malformed: Error {}

    static func declaring(width: Int, height: Int, in jpeg: Data) throws -> Data {
        var bytes = [UInt8](jpeg)
        // Marker FFC0–FFC2, then length (2), precision (1), height (2), width (2).
        guard
            let marker = bytes.indices.dropLast(9).first(where: {
                bytes[$0] == 0xFF && (0xC0...0xC2).contains(bytes[$0 + 1])
            })
        else { throw Malformed() }
        bytes[marker + 5] = UInt8(height >> 8)
        bytes[marker + 6] = UInt8(height & 0xFF)
        bytes[marker + 7] = UInt8(width >> 8)
        bytes[marker + 8] = UInt8(width & 0xFF)
        return Data(bytes)
    }
}
