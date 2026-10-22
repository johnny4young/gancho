import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pixel size and format of an image clip, read from the image header when it
/// is stored. Not synced: each device reads it from its own copy.
public struct ClipImageInfo: Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// The stored image's uniform type identifier, e.g. `public.png`.
    public var typeIdentifier: String?

    public init(width: Int, height: Int, typeIdentifier: String? = nil) {
        self.width = width
        self.height = height
        self.typeIdentifier = typeIdentifier
    }

    /// The short format name shown in rows: "PNG", "JPEG", "HEIC".
    public var formatName: String? {
        guard let typeIdentifier, let type = UTType(typeIdentifier) else { return nil }
        return type.preferredFilenameExtension?.uppercased()
    }

    /// The row's detail after "Image ·" when the clip has no title
    /// ("1200 × 800 · PNG"), or under its title ("PNG · 1200 × 800").
    public func rowDetail(titled: Bool) -> String {
        let size = "\(width) × \(height)"
        guard let formatName else { return size }
        return titled ? "\(formatName) · \(size)" : "\(size) · \(formatName)"
    }

    /// The displayed size from the header alone (no pixel decode), with EXIF
    /// orientations 5–8 swapping width and height. Nil when the data is not an
    /// image ImageIO can read.
    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options)
                as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }
}
