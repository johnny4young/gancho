import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The exact pixels a user reviews before an image is shared over MCP: the
/// first frame, oriented, bounded, and re-encoded without any source metadata
/// (EXIF, GPS, color-profile comments, maker notes).
public struct ReviewedImageDerivative: Sendable, Equatable {
    /// Longest side after resampling. Larger images are scaled down.
    public static let maximumPixelSize = 1_568
    /// Rejected from the header alone, before anything is decoded.
    public static let maximumSourcePixels = 50_000_000
    /// Encoded size before base64, which adds a third on the wire.
    public static let maximumEncodedBytes = 2_000_000

    public enum Failure: Error, Equatable {
        case unreadable, tooManyPixels, tooLarge
    }

    public let data: Data
    public let mimeType: String
    public let width: Int
    public let height: Int

    public var sha256: String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// PNG keeps screenshot text sharp; JPEG is the fallback when PNG is too big.
    public static func make(from source: Data) throws -> ReviewedImageDerivative {
        guard let image = CGImageSourceCreateWithData(source as CFData, nil),
            CGImageSourceGetCount(image) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil)
                as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { throw Failure.unreadable }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixels <= maximumSourcePixels else { throw Failure.tooManyPixels }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maximumPixelSize, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let frame = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary)
        else { throw Failure.unreadable }

        for (type, mimeType, quality) in [
            (UTType.png, "image/png", nil), (UTType.jpeg, "image/jpeg", 0.85)
        ] as [(UTType, String, Double?)] {
            let encoded = try encode(frame, as: type, quality: quality)
            if encoded.count <= maximumEncodedBytes {
                return ReviewedImageDerivative(
                    data: encoded, mimeType: mimeType, width: frame.width, height: frame.height)
            }
        }
        throw Failure.tooLarge
    }

    /// No properties are copied from the source, so none of its metadata survives.
    private static func encode(_ frame: CGImage, as type: UTType, quality: Double?) throws -> Data {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, type.identifier as CFString, 1, nil)
        else { throw Failure.unreadable }
        let properties = quality.map {
            [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, frame, properties)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return output as Data
    }
}
