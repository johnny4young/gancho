import Foundation
import GanchoKit
import SwiftUI
import Testing

@testable import GanchoDesign

/// A 1×1 PNG — the same fixture `GRDBClipboardStoreTests` uses.
private let onePixelPNG = Data(
    base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)!

/// The shared thumbnail cache both apps wrap: load gating (kind/sensitive/
/// in-flight), idempotence, and the FIFO cap that keeps a long-lived session's
/// memory bounded.
@Suite("ClipThumbnailStore")
@MainActor
struct ClipThumbnailStoreTests {
    /// Counts `imageData` reads so tests can assert the load path short-circuits.
    @MainActor private final class LoadCounter {
        var value = 0
    }

    private func makeStore(
        maxCached: Int = 64,
        skipsSensitiveClips: Bool = true,
        loads: LoadCounter? = nil
    ) -> ClipThumbnailStore {
        ClipThumbnailStore(
            maxCached: maxCached,
            maxPixel: 480,
            skipsSensitiveClips: skipsSensitiveClips,
            decodePriority: nil,
            imageData: { _ in
                loads?.value += 1
                return onePixelPNG
            })
    }

    @Test("Library-sized cache tolerates corrupt thumbnail bytes without retaining an image")
    func corruptLibraryThumbnail() async {
        let store = ClipThumbnailStore(
            maxCached: 64, maxPixel: 256,
            skipsSensitiveClips: true, decodePriority: .utility, imageData: { _ in Data([1, 2, 3]) }
        )
        let item = ClipItem(kind: .image)
        await store.ensureLoaded(item)
        #expect(store.cached(for: item.id) == nil)
    }

    @Test("Library-sized cache stays bounded while browsing many image clips")
    func boundedLibraryThumbnails() async {
        let store = makeStore(maxCached: 4)
        let items = (0..<2_000).map { _ in ClipItem(kind: .image) }
        for item in items { await store.ensureLoaded(item) }
        #expect(items.filter { store.cached(for: $0.id) != nil }.count == 4)
        #expect(store.cached(for: items[0].id) == nil)
        #expect(store.cached(for: items[1_999].id) != nil)
    }

    @Test("Decodes and caches an image clip's thumbnail")
    func cachesImageClip() async {
        let store = makeStore()
        let item = ClipItem(kind: .image)
        #expect(store.cached(for: item.id) == nil)
        await store.ensureLoaded(item)
        #expect(store.cached(for: item.id) != nil)
    }

    @Test("Never loads non-image clips, and skips sensitive ones when asked to")
    func skipsNonImageAndSensitive() async {
        let loads = LoadCounter()
        let store = makeStore(skipsSensitiveClips: true, loads: loads)
        await store.ensureLoaded(ClipItem(kind: .text))
        let sensitive = ClipItem(kind: .image, isSensitive: true)
        await store.ensureLoaded(sensitive)
        #expect(loads.value == 0)
        #expect(store.cached(for: sensitive.id) == nil)
    }

    @Test("The macOS policy (skipsSensitiveClips: false) still decodes sensitive images")
    func macPolicyDecodesSensitive() async {
        let store = makeStore(skipsSensitiveClips: false)
        let sensitive = ClipItem(kind: .image, isSensitive: true)
        await store.ensureLoaded(sensitive)
        #expect(store.cached(for: sensitive.id) != nil)
    }

    @Test("ensureLoaded is idempotent — a cached clip is never re-read")
    func idempotentLoad() async {
        let loads = LoadCounter()
        let store = makeStore(loads: loads)
        let item = ClipItem(kind: .image)
        await store.ensureLoaded(item)
        await store.ensureLoaded(item)
        #expect(loads.value == 1)
    }

    @Test("FIFO cap evicts the oldest entry; newer entries stay cached")
    func fifoEviction() async {
        let store = makeStore(maxCached: 2)
        let first = ClipItem(kind: .image)
        let second = ClipItem(kind: .image)
        let third = ClipItem(kind: .image)
        await store.ensureLoaded(first)
        await store.ensureLoaded(second)
        await store.ensureLoaded(third)
        #expect(store.cached(for: first.id) == nil)
        #expect(store.cached(for: second.id) != nil)
        #expect(store.cached(for: third.id) != nil)
    }

    @Test("Downsampler produces PNG data for a valid image and nil for junk")
    func downsampler() {
        let png = ClipThumbnailStore.thumbnailPNGData(from: onePixelPNG, maxPixel: 480)
        #expect(png != nil)
        #expect(ClipThumbnailStore.thumbnailPNGData(from: Data("junk".utf8), maxPixel: 480) == nil)
    }
}
