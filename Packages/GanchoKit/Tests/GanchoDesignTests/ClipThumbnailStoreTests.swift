import Foundation
import GanchoKit
import SwiftUI
import Synchronization
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
@Suite("ClipThumbnailStore", .timeLimit(.minutes(1)))
@MainActor
struct ClipThumbnailStoreTests {
    @MainActor private final class ImageReadGate {
        var continuation: CheckedContinuation<Data?, Never>?
        var entered = false

        func read() async -> Data? {
            entered = true
            return await withCheckedContinuation { continuation = $0 }
        }

        func waitUntilEntered() async {
            while !entered { await Task.yield() }
        }

        func release() {
            continuation?.resume(returning: onePixelPNG)
            continuation = nil
        }
    }

    @Test("A cancelled row releases unused work and cannot publish a late decode")
    func cancelledConsumerReleasesRead() async {
        let gate = ImageReadGate()
        let store = ClipThumbnailStore(
            maxCached: 2, maxPixel: 480, skipsSensitiveClips: true, decodePriority: nil,
            imageData: { _ in await gate.read() })
        let item = ClipItem(kind: .image)
        let pending = Task { await store.ensureLoaded(item) }
        await gate.waitUntilEntered()
        pending.cancel()
        let deadline = ContinuousClock.now + .seconds(5)
        while store.pendingLoadCount > 0, ContinuousClock.now < deadline { await Task.yield() }
        #expect(store.pendingLoadCount == 0)
        gate.release()
        await pending.value
        #expect(store.cached(for: item.id) == nil)
    }

    @Test("A clip protected in storage during the read is not cached under its old revision")
    func storageChangeDuringReadIsDropped() async {
        let gate = ImageReadGate()
        let item = ClipItem(kind: .image)
        var persisted = item
        let store = ClipThumbnailStore(
            maxCached: 2, maxPixel: 480, skipsSensitiveClips: true, decodePriority: nil,
            revision: { _ in persisted }, imageData: { _ in await gate.read() })
        let pending = Task { await store.ensureLoaded(item) }
        await gate.waitUntilEntered()
        persisted.isSensitive = true
        gate.release()
        await pending.value
        #expect(store.cached(for: item) == nil)
        #expect(store.cached(for: item.id) == nil)
    }

    @Test("Text rows do not notify thumbnail readers when nothing is cached")
    func nonImageRowsDoNotInvalidateObservers() async {
        let store = makeStore()
        let image = ClipItem(kind: .image)
        await store.ensureLoaded(image)
        let notified = Mutex(false)
        withObservationTracking {
            _ = store.cached(for: image)
        } onChange: {
            notified.withLock { $0 = true }
        }
        for _ in 0..<20 { await store.ensureLoaded(ClipItem(kind: .text)) }
        #expect(!notified.withLock { $0 })
        #expect(store.cached(for: image) != nil)
    }

    @Test("One cancelled consumer cannot cancel another visible view's shared thumbnail")
    func concurrentConsumersShareRead() async {
        let gate = ImageReadGate()
        let loads = LoadCounter()
        let store = ClipThumbnailStore(
            maxCached: 2, maxPixel: 480, skipsSensitiveClips: true, decodePriority: nil,
            imageData: { _ in
                loads.value += 1
                return await gate.read()
            })
        let item = ClipItem(kind: .image)
        let first = Task { await store.ensureLoaded(item) }
        await gate.waitUntilEntered()
        let second = Task { await store.ensureLoaded(item) }
        let deadline = ContinuousClock.now + .seconds(5)
        while store.pendingConsumerCount(for: item.id) < 2, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(store.pendingConsumerCount(for: item.id) == 2)
        first.cancel()
        gate.release()
        await first.value
        await second.value
        #expect(loads.value == 1)
        #expect(store.cached(for: item.id) != nil)
        #expect(store.pendingLoadCount == 0)
    }

    @Test("A changed content revision reloads the thumbnail; usage bookkeeping does not")
    func contentChangesInvalidateCachedImages() async {
        let loads = LoadCounter()
        let store = makeStore(loads: loads)
        var item = ClipItem(kind: .image, contentHash: "first")
        await store.ensureLoaded(item)
        item.uses += 1
        item.lastUsedAt = .now
        await store.ensureLoaded(item)
        #expect(loads.value == 1)
        item.updatedAt = item.updatedAt.addingTimeInterval(1)
        await store.ensureLoaded(item)
        #expect(loads.value == 2)
        item.contentHash = "second"
        await store.ensureLoaded(item)
        #expect(loads.value == 3)
        #expect(store.cached(for: item.id) != nil)
    }

    @Test("Protected metadata invalidates both a cached image and a suspended read")
    func privacyChangeRejectsExistingAndLateImages() async {
        let cachedStore = makeStore()
        var item = ClipItem(kind: .image, contentHash: "image")
        await cachedStore.ensureLoaded(item)
        item.isSensitive = true
        await cachedStore.ensureLoaded(item)
        #expect(cachedStore.cached(for: item.id) == nil)
        #expect(cachedStore.cachedAccent(for: item.id) == nil)

        item.isSensitive = false
        let gate = ImageReadGate()
        let pendingStore = ClipThumbnailStore(
            maxCached: 2, maxPixel: 480, skipsSensitiveClips: true, decodePriority: nil,
            imageData: { _ in await gate.read() })
        let original = item
        let pending = Task { await pendingStore.ensureLoaded(original) }
        await gate.waitUntilEntered()
        item.isSensitive = true
        await pendingStore.ensureLoaded(item)
        gate.release()
        await pending.value
        #expect(pendingStore.cached(for: item.id) == nil)
    }

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
