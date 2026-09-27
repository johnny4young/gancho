import CoreGraphics
import Foundation
import GanchoKit
import ImageIO
import Testing

@testable import GanchoDesign

/// The thumbnail's average colour rides along with the decode: a solid image
/// yields its own colour, a fully transparent one yields nothing.
@Suite("ClipThumbnailStore — accent colour")
struct ClipThumbnailAccentTests {
    private func solidImage(
        red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1
    )
        -> CGImage
    {
        let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
    }

    @Test("A solid teal reads back as teal")
    func solid() throws {
        let accent = try #require(
            ClipThumbnailStore.averageColor(of: solidImage(red: 0, green: 0.5, blue: 0.5)))
        #expect(abs(accent.red - 0) < 0.02)
        #expect(abs(accent.green - 0.5) < 0.02)
        #expect(abs(accent.blue - 0.5) < 0.02)
    }

    @Test("Two halves average to their mix, not to either half")
    func halves() throws {
        let context = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 8, y: 0, width: 8, height: 16))
        let accent = try #require(ClipThumbnailStore.averageColor(of: context.makeImage()!))
        #expect(abs(accent.red - 0.5) < 0.1)
        #expect(accent.green < 0.05)
        #expect(abs(accent.blue - 0.5) < 0.1)
    }

    @Test("A transparent region is left out of the mean rather than darkening it")
    func partiallyTransparent() throws {
        let context = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        let accent = try #require(ClipThumbnailStore.averageColor(of: context.makeImage()!))
        #expect(accent.green > 0.9)
        #expect(accent.red < 0.05)
    }

    @Test("A transparent image has no accent")
    func transparent() {
        #expect(
            ClipThumbnailStore.averageColor(of: solidImage(red: 1, green: 0, blue: 0, alpha: 0))
                == nil)
    }

    @Test("The decode returns the PNG and the accent together")
    func decode() throws {
        let png = try #require(
            ClipThumbnailStore.thumbnailPNGData(
                from: pngData(solidImage(red: 1, green: 0, blue: 0)), maxPixel: 4))
        let decoded = try #require(ClipThumbnailStore.decodeThumbnail(from: png, maxPixel: 4))
        #expect(!decoded.0.isEmpty)
        #expect(decoded.1?.red ?? 0 > 0.9)
    }

    private func pngData(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
