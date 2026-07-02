import AppKit
import GanchoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Lazily loads and caches small thumbnails for image clips so the history rows
/// (and the peek) can show a real preview without re-reading the blob on every
/// render or navigation. Each image is decoded once — off the main actor, via
/// ImageIO so only a downscaled thumbnail is produced — and cached by clip id.
/// The cache is FIFO-capped: a menu-bar agent lives for weeks, and an unbounded
/// [UUID: Image] would grow monotonically while browsing image-heavy history.
@Observable
@MainActor
final class ClipThumbnailStore {
    private var cache: [UUID: Image] = [:]
    @ObservationIgnored private var cacheOrder: [UUID] = []
    @ObservationIgnored private let maxCached = 64
    @ObservationIgnored private var loading: Set<UUID> = []
    @ObservationIgnored private let imageData: (UUID) async -> Data?

    /// - Parameter imageData: reads a clip's raw image bytes (the `.binary`
    ///   blob), or nil when the clip isn't an image / can't be read.
    init(imageData: @escaping (UUID) async -> Data?) {
        self.imageData = imageData
    }

    /// The cached thumbnail, if already loaded. Pure — never triggers a load,
    /// so it's safe to call from a view body.
    func cached(for id: UUID) -> Image? { cache[id] }

    /// Decode + cache an image clip's thumbnail if not already done. Idempotent;
    /// drive it from a row's `.task` so only visible image rows load.
    func ensureLoaded(_ item: ClipItem) async {
        guard item.kind == .image, cache[item.id] == nil, !loading.contains(item.id)
        else { return }
        loading.insert(item.id)
        defer { loading.remove(item.id) }

        guard let data = await imageData(item.id) else { return }
        // 480 px keeps the peek crisp (it shows the image up to ~220 pt @2x);
        // the 30 pt row tile just downsamples further.
        let thumbnail = await Task.detached(priority: .utility) {
            ClipThumbnailStore.thumbnailData(from: data, maxPixel: 480)
        }.value
        if let thumbnail, let image = NSImage(data: thumbnail) {
            cache[item.id] = Image(nsImage: image)
            // FIFO cap (mirrors the keyboard extension's pattern): evict the
            // oldest entry so a long-lived agent session stays bounded. An
            // evicted-then-revisited row simply reloads via `ensureLoaded`.
            cacheOrder.append(item.id)
            if cacheOrder.count > maxCached {
                let evicted = cacheOrder.removeFirst()
                if evicted != item.id { cache[evicted] = nil }
            }
        }
    }

    /// A downscaled PNG thumbnail via ImageIO (decodes only what it needs).
    /// `nonisolated` so it runs off the main actor; returns Sendable `Data`.
    nonisolated static func thumbnailData(from data: Data, maxPixel: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
