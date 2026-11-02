import CoreGraphics
import Foundation
import ImageIO

/// The notch shelf's image actions, on-device through ImageIO.
public enum ImageEdits {
    public static let resizedLongEdge = 1280

    public enum Outcome: Equatable, Sendable {
        case edited(Data, typeIdentifier: String)
        /// Already within the limit, or nothing to remove.
        case unchanged
        case failed
    }

    /// Scales the long edge down to `longEdge`, keeping the aspect ratio and
    /// baking the orientation in; never enlarges.
    public static func resize(_ data: Data, longEdge: Int = resizedLongEdge) -> Outcome {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return .failed }
        guard max(width, height) > longEdge else { return .unchanged }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return .failed }
        let type = outputType(of: source)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil)
        else { return .failed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return .failed }
        return .edited(output as Data, typeIdentifier: type)
    }

    /// Removes the GPS metadata and keeps the rest, orientation included;
    /// JPEG, PNG, TIFF and HEIC are copied without re-encoding.
    public static func stripLocation(_ data: Data) -> Outcome {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source) as String?
        else { return .failed }
        guard hasLocation(source) else { return .unchanged }
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
            return .failed
        }
        // Without its metadata passed back in, the copy drops all of it.
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata, kCGImageDestinationMergeMetadata: true,
            kCGImageMetadataShouldExcludeGPS: true
        ]
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, type as CFString, 1, nil),
            CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, nil)
        else { return .failed }
        return .edited(output as Data, typeIdentifier: type)
    }

    public static func hasLocation(_ data: Data) -> Bool {
        CGImageSourceCreateWithData(data as CFData, nil).map(hasLocation) ?? false
    }

    private static func hasLocation(_ source: CGImageSource) -> Bool {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyGPSDictionary] != nil
    }

    /// The source's own format when ImageIO can write it, PNG otherwise.
    private static func outputType(of source: CGImageSource) -> String {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        guard let type = CGImageSourceGetType(source) as String?, writable.contains(type) else {
            return "public.png"
        }
        return type
    }
}
