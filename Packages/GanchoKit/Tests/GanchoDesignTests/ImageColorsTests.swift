import CoreGraphics
import Foundation
import GanchoKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import GanchoDesign

@Suite("Image colours — dominant swatches and the pixel under a click")
struct ImageColorsTests {
    /// Vertical bands, left to right, each `(width, colour)`, 64 px tall.
    private func bands(_ bands: [(Int, ColorValue?)]) -> CGImage {
        let width = bands.map(\.0).reduce(0, +)
        let context = CGContext(
            data: nil, width: width, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var x = 0
        for (bandWidth, color) in bands {
            if let color {
                let unit = color.unit
                context.setFillColor(
                    CGColor(
                        srgbRed: unit.red, green: unit.green, blue: unit.blue, alpha: unit.alpha))
                context.fill(CGRect(x: x, y: 0, width: bandWidth, height: 64))
            }
            x += bandWidth
        }
        return context.makeImage()!
    }

    private func png(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private let orange = ColorValue(red: 243, green: 155, blue: 58)
    private let blue = ColorValue(red: 37, green: 99, blue: 235)
    private let ink = ColorValue(red: 29, green: 29, blue: 31)

    private func close(_ lhs: ColorValue, _ rhs: ColorValue) -> Bool {
        abs(lhs.red - rhs.red) <= 8 && abs(lhs.green - rhs.green) <= 8
            && abs(lhs.blue - rhs.blue) <= 8
    }

    @Test("Three bands come back as three swatches, most area first")
    func threeColoursInDominanceOrder() {
        let colors = ImageColors.dominant(in: bands([(32, blue), (64, orange), (32, ink)]))
        #expect(colors.count == 3)
        #expect(close(colors[0], orange))
        #expect(colors.dropFirst().contains { close($0, blue) })
        #expect(colors.dropFirst().contains { close($0, ink) })
    }

    @Test("A flat image yields one swatch; transparency counts for nothing")
    func flatAndTransparent() {
        let flat = ImageColors.dominant(in: bands([(64, orange)]))
        #expect(flat.count == 1)
        #expect(close(flat[0], orange))
        let half = ImageColors.dominant(in: bands([(32, nil), (32, blue)]))
        #expect(half.count == 1)
        #expect(close(half[0], blue))
        #expect(ImageColors.dominant(in: bands([(64, nil)])).isEmpty)
    }

    @Test("A click maps through the scaled-to-fit letterbox to the image's pixel")
    func pointToPixel() {
        // A 200 × 100 image fit into a 100 × 100 view: 50 pt letterbox bands
        // top and bottom, 0.5 pt per pixel.
        let view = CGSize(width: 100, height: 100)
        let image = CGSize(width: 200, height: 100)
        #expect(ImageColors.pixel(at: CGPoint(x: 0, y: 25), in: view, imageSize: image) == .zero)
        #expect(
            ImageColors.pixel(at: CGPoint(x: 99.9, y: 74.9), in: view, imageSize: image)
                == CGPoint(x: 199, y: 99))
        #expect(ImageColors.pixel(at: CGPoint(x: 50, y: 10), in: view, imageSize: image) == nil)
        #expect(ImageColors.pixel(at: CGPoint(x: 50, y: 80), in: view, imageSize: image) == nil)
        #expect(ImageColors.pixel(at: .zero, in: .zero, imageSize: image) == nil)
    }

    @Test("The sampled pixel is the source's exact colour, not a resampled one")
    func exactPixel() throws {
        let data = png(bands([(3, blue), (1, orange), (3, ink)]))
        #expect(ImageColors.color(atPixel: CGPoint(x: 3, y: 10), in: data) == orange)
        #expect(ImageColors.color(atPixel: CGPoint(x: 0, y: 63), in: data) == blue)
        #expect(ImageColors.color(atPixel: CGPoint(x: 7, y: 0), in: data) == nil, "outside")
    }

    @Test("An image past the sampling cap is read from a capped decode")
    func cappedDecode() throws {
        // A 64 × 64 image of two halves, sampled from a 4 × 4 decode.
        let data = png(bands([(32, blue), (32, orange)]))
        let left = try #require(
            ImageColors.color(atPixel: CGPoint(x: 8, y: 8), in: data, maximumSide: 4))
        let right = try #require(
            ImageColors.color(atPixel: CGPoint(x: 56, y: 8), in: data, maximumSide: 4))
        #expect(close(left, blue))
        #expect(close(right, orange))
    }

    @Test("The last row and column of a capped decode still sample")
    func cappedDecodeEdges() throws {
        // ImageIO rounds a capped decode's size, so a mapped edge pixel can
        // land one past it.
        let unit = orange.unit
        for height in 1...12 {
            let context = CGContext(
                data: nil, width: 63, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(
                CGColor(srgbRed: unit.red, green: unit.green, blue: unit.blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 63, height: height))
            let data = png(context.makeImage()!)
            let corner = CGPoint(x: 62, y: height - 1)
            let color = ImageColors.color(atPixel: corner, in: data, maximumSide: 32)
            #expect(color.map { close($0, orange) } == true, "63 × \(height)")
        }
    }
}
