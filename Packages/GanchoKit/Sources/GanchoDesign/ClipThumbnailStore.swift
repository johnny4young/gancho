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
/// detail views, replacing two near-identical per-app copies.
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
/// The average colour of a thumbnail, as sRGB components so it crosses the
/// decode task as a plain value.
public struct ThumbnailAccent: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
}

/// One decode's output, crossing from the detached task to the main actor.
struct DecodedThumbnail: Sendable {
    let png: Data
    let accent: ThumbnailAccent?
    let palette: [ColorValue]
}

@Observable
@MainActor
public final class ClipThumbnailStore {
    private var cache: [UUID: Image] = [:]
    private var accents: [UUID: ThumbnailAccent] = [:]
    private var palettes: [UUID: [ColorValue]] = [:]
    @ObservationIgnored private var cacheOrder: [UUID] = []
    private var versions: [UUID: ClipContentVersion] = [:]
    @ObservationIgnored private var loading: [UUID: PendingThumbnail] = [:]

    private struct PendingThumbnail {
        let version: ClipContentVersion
        let token: UUID
        let task: Task<DecodedThumbnail?, Never>
        var consumers: Set<UUID> = []
    }
    @ObservationIgnored private let maxCached: Int
    @ObservationIgnored private let maxPixel: CGFloat
    @ObservationIgnored private let skipsSensitiveClips: Bool
    @ObservationIgnored private let decodePriority: TaskPriority?
    @ObservationIgnored private let imageData: @MainActor (UUID) async -> Data?
    @ObservationIgnored private let revision: (@MainActor (UUID) async -> ClipItem?)?

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
    ///   - revision: when set, re-reads the persisted row after the decode so
    ///     a clip edited, expired or newly protected during the read is dropped.
    ///   - imageData: reads a clip's raw image bytes (the `.binary` blob), or
    ///     nil when the clip isn't an image / can't be read.
    public init(
        maxCached: Int,
        maxPixel: CGFloat,
        skipsSensitiveClips: Bool,
        decodePriority: TaskPriority?,
        revision: (@MainActor (UUID) async -> ClipItem?)? = nil,
        imageData: @escaping @MainActor (UUID) async -> Data?
    ) {
        self.maxCached = maxCached
        self.maxPixel = maxPixel
        self.skipsSensitiveClips = skipsSensitiveClips
        self.decodePriority = decodePriority
        self.revision = revision
        self.imageData = imageData
    }

    /// The cached thumbnail, if already loaded. Pure — never triggers a load,
    /// so it's safe to call from a view body.
    func cached(for id: UUID) -> Image? { cache[id] }

    /// The thumbnail's average colour, once it is loaded. Pure like `cached`.
    func cachedAccent(for id: UUID) -> ThumbnailAccent? { accents[id] }

    /// Content-bound reads prevent a changed or newly protected clip from
    /// rendering a cached bitmap before its replacement task begins.
    public func cached(for item: ClipItem) -> Image? {
        guard !(skipsSensitiveClips && ClipSafePresentation.requiresMasking(item)),
            versions[item.id] == ClipContentVersion(item)
        else { return nil }
        return cache[item.id]
    }

    public func cachedAccent(for item: ClipItem) -> ThumbnailAccent? {
        guard cached(for: item) != nil else { return nil }
        return accents[item.id]
    }

    /// The thumbnail's dominant colours, most common first, once it is loaded.
    public func cachedPalette(for item: ClipItem) -> [ColorValue] {
        // A masked image's colours are as revealing as its thumbnail.
        guard !ClipSafePresentation.requiresMasking(item), cached(for: item) != nil else {
            return []
        }
        return palettes[item.id] ?? []
    }

    /// All views requesting the same content await one read/decode. A changed
    /// version invalidates the old request, whose late result cannot publish.
    public func ensureLoaded(_ item: ClipItem) async {
        guard !Task.isCancelled else { return }
        guard item.kind == .image,
            !(skipsSensitiveClips && ClipSafePresentation.requiresMasking(item))
        else {
            invalidate(item.id)
            return
        }
        let version = ClipContentVersion(item)
        if versions[item.id] == version, cache[item.id] != nil { return }
        let pending: PendingThumbnail
        if let existing = loading[item.id], existing.version == version {
            pending = existing
        } else {
            invalidate(item.id)
            pending = PendingThumbnail(
                version: version, token: UUID(), task: loadTask(id: item.id, version: version))
            loading[item.id] = pending
        }
        let consumer = UUID()
        loading[item.id]?.consumers.insert(consumer)
        defer { releaseConsumer(consumer, id: item.id, token: pending.token) }
        let decodedThumbnail = await withTaskCancellationHandler {
            await pending.task.value
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.releaseConsumer(consumer, id: item.id, token: pending.token)
            }
        }
        guard !Task.isCancelled, loading[item.id]?.token == pending.token else { return }
        loading[item.id] = nil
        guard let decodedThumbnail else { return }
        #if canImport(AppKit)
            guard let decoded = NSImage(data: decodedThumbnail.png) else { return }
            let image = Image(nsImage: decoded)
        #else
            guard let decoded = UIImage(data: decodedThumbnail.png) else { return }
            let image = Image(uiImage: decoded)
        #endif
        cache[item.id] = image
        accents[item.id] = decodedThumbnail.accent
        palettes[item.id] = decodedThumbnail.palette
        versions[item.id] = version
        cacheOrder.append(item.id)
        if cacheOrder.count > maxCached {
            let evicted = cacheOrder.removeFirst()
            cache[evicted] = nil
            accents[evicted] = nil
            palettes[evicted] = nil
            versions[evicted] = nil
        }
    }

    private func loadTask(
        id: UUID, version: ClipContentVersion
    ) -> Task<DecodedThumbnail?, Never> {
        let imageData = self.imageData
        let revision = self.revision
        let requiresEligibility = skipsSensitiveClips
        let maxPixel = self.maxPixel
        let priority = decodePriority
        return Task { @MainActor in
            guard !Task.isCancelled, let data = await imageData(id), !Task.isCancelled
            else { return nil }
            let decoded = await Task.detached(priority: priority) {
                ClipThumbnailStore.decodeThumbnail(from: data, maxPixel: maxPixel)
            }.value
            if let revision {
                guard let current = await revision(id),
                    ClipContentVersion(current) == version,
                    !requiresEligibility || ClipSafeDelivery.isEligible(current)
                else { return nil }
            }
            return Task.isCancelled ? nil : decoded
        }
    }

    private func invalidate(_ id: UUID) {
        loading.removeValue(forKey: id)?.task.cancel()
        // Observation fires on every write; text rows must not redraw thumbnail readers.
        guard cache[id] != nil || accents[id] != nil || versions[id] != nil else { return }
        cache[id] = nil
        accents[id] = nil
        palettes[id] = nil
        versions[id] = nil
        cacheOrder.removeAll { $0 == id }
    }

    /// Leaving the viewport cancels unused work, but one disappearing view
    /// cannot cancel the decode another visible view is still awaiting.
    private func releaseConsumer(_ consumer: UUID, id: UUID, token: UUID) {
        guard loading[id]?.token == token else { return }
        loading[id]?.consumers.remove(consumer)
        if loading[id]?.consumers.isEmpty == true {
            loading.removeValue(forKey: id)?.task.cancel()
        }
    }

    var pendingLoadCount: Int { loading.count }
    func pendingConsumerCount(for id: UUID) -> Int { loading[id]?.consumers.count ?? 0 }

    /// The thumbnail PNG with its average and dominant colours, all Sendable,
    /// from one ImageIO decode.
    nonisolated static func decodeThumbnail(
        from data: Data, maxPixel: CGFloat
    ) -> DecodedThumbnail? {
        guard let cgImage = thumbnailImage(from: data, maxPixel: maxPixel),
            let png = pngData(from: cgImage)
        else { return nil }
        return DecodedThumbnail(
            png: png, accent: averageColor(of: cgImage),
            palette: ImageColors.dominant(in: cgImage))
    }

    /// Draws the thumbnail into a small grid and averages it, alpha-weighted.
    /// A single resampled pixel is a filtered sample of a limited footprint,
    /// not a mean; a grid of them is close enough to one at negligible cost.
    nonisolated static func averageColor(of image: CGImage) -> ThumbnailAccent? {
        let side = Self.averageGridSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &pixels, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        // Premultiplied channels summed over alpha summed is the un-premultiplied
        // mean, so a transparent region neither darkens nor counts.
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var alpha = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            red += Double(pixels[offset]) / 255
            green += Double(pixels[offset + 1]) / 255
            blue += Double(pixels[offset + 2]) / 255
            alpha += Double(pixels[offset + 3]) / 255
        }
        guard alpha > 0 else { return nil }
        return ThumbnailAccent(
            red: min(1, red / alpha), green: min(1, green / alpha), blue: min(1, blue / alpha))
    }

    /// Pixels per side of the averaging grid.
    nonisolated static let averageGridSide = 8

    /// A downscaled PNG thumbnail via ImageIO: reads only enough of the source
    /// to build a thumbnail at `maxPixel`, honouring EXIF orientation.
    /// `nonisolated` so it runs off the main actor; returns Sendable `Data`.
    nonisolated static func thumbnailPNGData(from data: Data, maxPixel: CGFloat) -> Data? {
        thumbnailImage(from: data, maxPixel: maxPixel).flatMap(pngData(from:))
    }

    nonisolated private static func thumbnailImage(from data: Data, maxPixel: CGFloat) -> CGImage? {
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
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    nonisolated private static func pngData(from cgImage: CGImage) -> Data? {
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
