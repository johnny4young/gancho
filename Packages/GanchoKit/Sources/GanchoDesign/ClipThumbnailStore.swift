import CoreGraphics
import Foundation
import GanchoKit
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Lazily decodes and caches small `SwiftUI.Image` thumbnails for image clips —
/// the one thumbnail cache shared by the macOS panel/peek and the iOS history/
/// detail views (previously two near-identical per-app copies; A3-2.7/F-1.3).
///
/// Each image is decoded once, off the main actor, via ImageIO so only a
/// downscaled thumbnail is ever produced (never the full-resolution bitmap),
/// and cached by clip id. The cache is FIFO-capped — the keyboard extension's
/// proven pattern — because an unbounded `[UUID: Image]` would grow
/// monotonically while browsing image-heavy history (a menu-bar agent lives
/// for weeks).
///
/// Platform policy stays at the edge: each app's `ClipThumbnailStore.swift`
/// wrapper picks the cap, decode priority, and sensitive-clip handling, so the
/// unification is behavior-identical per platform.
@Observable
@MainActor
public final class ClipThumbnailStore {
    private var cache: [UUID: Image] = [:]
    @ObservationIgnored private var cacheOrder: [UUID] = []
    @ObservationIgnored private var loading: Set<UUID> = []
    @ObservationIgnored private let maxCached: Int
    @ObservationIgnored private let maxPixel: CGFloat
    @ObservationIgnored private let skipsSensitiveClips: Bool
    @ObservationIgnored private let decodePriority: TaskPriority?
    @ObservationIgnored private let imageData: @MainActor (UUID) async -> Data?

    /// - Parameters:
    ///   - maxCached: FIFO cap; an evicted-then-revisited row simply reloads
    ///     through `ensureLoaded`. 64 decoded thumbnails is plenty for a
    ///     visible list plus scroll-back (the keyboard extension uses 24).
    ///   - maxPixel: decode ceiling so a huge screenshot never blows up
    ///     memory. 480 px keeps the macOS peek and the iOS detail preview
    ///     crisp; row tiles just downsample further.
    ///   - skipsSensitiveClips: when true, sensitive image clips are never
    ///     decoded — they keep their masked preview (the iOS policy). macOS
    ///     historically decodes them (the peek masks at display time), so it
    ///     passes false to stay behavior-identical.
    ///   - decodePriority: priority for the detached decode task; nil uses
    ///     the runtime default.
    ///   - imageData: reads a clip's raw image bytes (the `.binary` blob), or
    ///     nil when the clip isn't an image / can't be read.
    public init(
        maxCached: Int,
        maxPixel: CGFloat,
        skipsSensitiveClips: Bool,
        decodePriority: TaskPriority?,
        imageData: @escaping @MainActor (UUID) async -> Data?
    ) {
        self.maxCached = maxCached
        self.maxPixel = maxPixel
        self.skipsSensitiveClips = skipsSensitiveClips
        self.decodePriority = decodePriority
        self.imageData = imageData
    }

    /// The cached thumbnail, if already loaded. Pure — never triggers a load,
    /// so it's safe to call from a view body.
    public func cached(for id: UUID) -> Image? { cache[id] }

    /// Decode + cache an image clip's thumbnail if not already done. Idempotent
    /// and in-flight-deduplicated; drive it from a row's `.task` so only
    /// visible image rows load.
    public func ensureLoaded(_ item: ClipItem) async {
        guard item.kind == .image, !(skipsSensitiveClips && item.isSensitive),
            cache[item.id] == nil, !loading.contains(item.id)
        else { return }
        loading.insert(item.id)
        defer { loading.remove(item.id) }

        guard let data = await imageData(item.id) else { return }
        // Decode off the main actor; the detached task returns Sendable PNG
        // `Data` (not a platform image) so this compiles under strict
        // concurrency on both platforms.
        let maxPixel = self.maxPixel
        let thumbnail = await Task.detached(priority: decodePriority) {
            ClipThumbnailStore.thumbnailPNGData(from: data, maxPixel: maxPixel)
        }.value
        guard let thumbnail else { return }
        #if canImport(AppKit)
            guard let decoded = NSImage(data: thumbnail) else { return }
            let image = Image(nsImage: decoded)
        #else
            guard let decoded = UIImage(data: thumbnail) else { return }
            let image = Image(uiImage: decoded)
        #endif
        cache[item.id] = image
        // FIFO cap (mirrors the keyboard extension's pattern): evict the
        // oldest entry so a long-lived session stays bounded.
        cacheOrder.append(item.id)
        if cacheOrder.count > maxCached {
            let evicted = cacheOrder.removeFirst()
            if evicted != item.id { cache[evicted] = nil }
        }
    }

    /// A downscaled PNG thumbnail via ImageIO: reads only enough of the source
    /// to build a thumbnail at `maxPixel`, honouring EXIF orientation.
    /// `nonisolated` so it runs off the main actor; returns Sendable `Data`.
    nonisolated static func thumbnailPNGData(from data: Data, maxPixel: CGFloat) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        // PNG-encode via ImageIO (platform-free) so the result is Sendable
        // `Data` on both platforms; the main actor re-wraps it as an Image.
        let encoded = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                encoded as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return encoded as Data
    }
}
