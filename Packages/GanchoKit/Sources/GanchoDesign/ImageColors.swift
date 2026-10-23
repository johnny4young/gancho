import CoreGraphics
import Foundation
import GanchoKit
import ImageIO

/// Colours read from an image clip, on-device: the few that dominate it, and
/// the exact pixel under a point of the fitted preview.
public enum ImageColors {
    /// Side of the grid the image is drawn into before counting colours.
    nonisolated static let gridSide = 16
    /// Two colours closer than this (sRGB, 0...255 per channel) count as one.
    nonisolated static let minimumDistance = 64.0
    /// A colour must cover this share of the opaque pixels to be listed.
    nonisolated static let minimumShare = 0.04

    /// Up to `maximum` distinct colours, most common first; one for a flat image.
    nonisolated public static func dominant(in image: CGImage, maximum: Int = 3) -> [ColorValue] {
        let side = gridSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard maximum > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        var bins: [Int: Bin] = [:]
        var opaque = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[offset + 3])
            // Mostly transparent pixels carry no colour worth naming.
            guard alpha >= 128 else { continue }
            let red = Int(pixels[offset]) * 255 / alpha
            let green = Int(pixels[offset + 1]) * 255 / alpha
            let blue = Int(pixels[offset + 2]) * 255 / alpha
            let key = (red >> 4) << 8 | (green >> 4) << 4 | blue >> 4
            bins[key, default: Bin()].add(red: red, green: green, blue: blue)
            opaque += 1
        }
        guard opaque > 0 else { return [] }
        var picked: [ColorValue] = []
        let ranked = bins.values.sorted { $0.count > $1.count }
        for bin in ranked where Double(bin.count) / Double(opaque) >= minimumShare {
            let color = ColorValue(
                red: bin.red / bin.count, green: bin.green / bin.count, blue: bin.blue / bin.count)
            guard picked.allSatisfy({ distance($0, color) >= minimumDistance }) else { continue }
            picked.append(color)
            if picked.count == maximum { break }
        }
        return picked
    }

    /// The pixel (top-left origin) under `point` in an image of `imageSize`
    /// pixels drawn `scaledToFit` into `viewSize`; nil in the letterbox.
    nonisolated public static func pixel(
        at point: CGPoint, in viewSize: CGSize, imageSize: CGSize
    ) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0, imageSize.width > 0, imageSize.height > 0
        else { return nil }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let origin = CGPoint(
            x: (viewSize.width - imageSize.width * scale) / 2,
            y: (viewSize.height - imageSize.height * scale) / 2)
        let x = ((point.x - origin.x) / scale).rounded(.down)
        let y = ((point.y - origin.y) / scale).rounded(.down)
        guard (0..<imageSize.width).contains(x), (0..<imageSize.height).contains(y) else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    /// The image's pixel size after its EXIF orientation, as the peek shows it.
    nonisolated public static func orientedSize(of data: Data) -> CGSize? {
        ClipImageInfo.pixelSize(of: data).map { CGSize(width: $0.width, height: $0.height) }
    }

    /// The exact colour of one pixel of the full-resolution, upright image.
    nonisolated public static func color(atPixel pixel: CGPoint, in data: Data) -> ColorValue? {
        guard let size = orientedSize(of: data),
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let upright = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height)
                ] as CFDictionary),
            let single = upright.cropping(
                to: CGRect(x: pixel.x, y: pixel.y, width: 1, height: 1)),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        guard
            let context = CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(single, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = Int(rgba[3])
        guard alpha > 0 else { return nil }
        let unpremultiplied = rgba.prefix(3).map { min(255, Int($0) * 255 / alpha) }
        return ColorValue(
            red: unpremultiplied[0], green: unpremultiplied[1], blue: unpremultiplied[2],
            alpha: alpha < 255 ? alpha : nil)
    }

    /// Summed channels of the pixels that fell in one coarse colour cell.
    private struct Bin {
        var count = 0
        var red = 0
        var green = 0
        var blue = 0

        mutating func add(red: Int, green: Int, blue: Int) {
            count += 1
            self.red += red
            self.green += green
            self.blue += blue
        }
    }

    nonisolated private static func distance(_ lhs: ColorValue, _ rhs: ColorValue) -> Double {
        let red = Double(lhs.red - rhs.red)
        let green = Double(lhs.green - rhs.green)
        let blue = Double(lhs.blue - rhs.blue)
        return (red * red + green * green + blue * blue).squareRoot()
    }
}
