import CryptoKit
import Foundation
import ImageIO

/// Content-addressed blob storage for binary clip payloads.
///
/// Files are named by their SHA-256, so identical content is stored once
/// and references can never dangle silently. Thumbnails are generated
/// LAZILY via ImageIO's downsampling (`kCGImageSourceThumbnailMaxPixelSize`)
/// which decodes at target size — the full-resolution bitmap NEVER enters
/// memory for list rendering. The full blob is read only for paste-back.
public struct BlobStore: Sendable {
    public let directory: URL
    private var thumbnailDirectory: URL {
        directory.appendingPathComponent("thumbnails", isDirectory: true)
    }

    /// Thumbnail bounding box in pixels. 256 covers list rows on Retina.
    public static let thumbnailMaxPixelSize = 256

    public init(directory: URL) {
        self.directory = directory
    }

    /// Stores the data (idempotent) and returns its content hash reference.
    @discardableResult
    public func write(_ data: Data) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = blobURL(for: hash)
        if !FileManager.default.fileExists(atPath: file.path) {
            try data.write(to: file, options: .atomic)
        }
        return hash
    }

    /// Full blob — paste-back only; UI code must use `thumbnailURL`.
    public func read(hash: String) throws -> Data? {
        let file = blobURL(for: hash)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    public func delete(hash: String) {
        try? FileManager.default.removeItem(at: blobURL(for: hash))
        try? FileManager.default.removeItem(at: thumbnailURLIfCached(for: hash))
    }

    /// Lazy thumbnail: generated on first request, cached on disk after.
    /// Returns nil when the blob is missing or not an image.
    public func thumbnailURL(for hash: String) throws -> URL? {
        let cached = thumbnailURLIfCached(for: hash)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let blob = blobURL(for: hash)
        guard FileManager.default.fileExists(atPath: blob.path),
            let source = CGImageSourceCreateWithURL(blob as CFURL, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailMaxPixelSize,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
        else { return nil }

        try FileManager.default.createDirectory(
            at: thumbnailDirectory, withIntermediateDirectories: true)
        guard
            let destination = CGImageDestinationCreateWithURL(
                cached as CFURL, "public.png" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return cached
    }

    private func blobURL(for hash: String) -> URL {
        directory.appendingPathComponent(hash)
    }

    private func thumbnailURLIfCached(for hash: String) -> URL {
        thumbnailDirectory.appendingPathComponent("\(hash).png")
    }
}
