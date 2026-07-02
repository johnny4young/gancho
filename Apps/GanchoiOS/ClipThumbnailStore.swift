import GanchoKit
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Decodes image clips into small, cached thumbnails for the history list and
/// the detail view — the iOS mirror of the macOS store. Decoding is downsampled
/// off the main actor via ImageIO (never the full-resolution image), and the
/// result is cached by clip id so scrolling a large history stays smooth.
/// Sensitive image clips are never decoded — they keep their masked preview.
/// The cache is FIFO-capped so an image-heavy session can't grow it without
/// bound — the same pattern the keyboard extension uses.
@Observable
@MainActor
final class ClipThumbnailStore {
    private var cache: [UUID: Image] = [:]
    private var cacheOrder: [UUID] = []
    private var inFlight: Set<UUID> = []
    private let store: any ClipboardStore
    /// FIFO cap: 64 decoded 480px thumbnails is plenty for a visible list plus
    /// scroll-back; anything evicted just reloads through `ensureLoaded`.
    private let maxCached = 64
    /// Cap the decode so a huge screenshot doesn't blow up memory; 480px covers
    /// both the row tile and the larger detail preview on a Retina phone.
    private let maxPixel: CGFloat = 480

    init(store: any ClipboardStore) {
        self.store = store
    }

    /// Pure getter for the view — returns the cached thumbnail or nil.
    func cached(for id: UUID) -> Image? { cache[id] }

    /// Loads and caches the thumbnail once. A no-op for non-images, sensitive
    /// clips, already-cached ids, and in-flight loads.
    func ensureLoaded(_ item: ClipItem) async {
        guard item.kind == .image, !item.isSensitive,
            cache[item.id] == nil, !inFlight.contains(item.id)
        else { return }
        inFlight.insert(item.id)
        defer { inFlight.remove(item.id) }
        guard case .binary(let data, _)? = try? await store.content(for: item.id) else { return }
        let maxPixel = self.maxPixel
        let decoded = await Task.detached { Self.downsample(data, maxPixel: maxPixel) }.value
        if let decoded {
            cache[item.id] = Image(uiImage: decoded)
            // Evict the oldest entry once past the cap (FIFO) so memory stays
            // bounded over a long browse.
            cacheOrder.append(item.id)
            if cacheOrder.count > maxCached {
                let evicted = cacheOrder.removeFirst()
                if evicted != item.id { cache[evicted] = nil }
            }
        }
    }

    /// Downsampled decode (ImageIO): reads only enough of the source to build a
    /// thumbnail at `maxPixel`, honouring EXIF orientation.
    nonisolated private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
