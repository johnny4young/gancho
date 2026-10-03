import Foundation
import GanchoDesign
import GanchoKit

/// The history/detail thumbnail cache is the shared
/// `GanchoDesign.ClipThumbnailStore` (one implementation for both apps); this
/// file only bakes in the iOS policy so every existing call site is unchanged.
typealias ClipThumbnailStore = GanchoDesign.ClipThumbnailStore

extension ClipThumbnailStore {
    /// History rows: decodes the store's small cached thumbnail, never the
    /// full blob. FIFO cap of 64, default decode priority, and sensitive
    /// image clips are never decoded — they keep their masked preview.
    convenience init(store: any ClipboardStore) {
        self.init(
            maxCached: 64,
            maxPixel: 480,
            skipsSensitiveClips: true,
            decodePriority: nil,
            imageData: { id in
                // The in-memory fallback has no thumbnail cache to read.
                guard let reader = store as? any ClipReading else {
                    return await ClipThumbnailStore.fullImageData(id, store: store)
                }
                return try? await reader.thumbnailData(for: id)
            })
    }

    /// The clip detail's preview: up to 340 pt tall, so it decodes from the
    /// full image at 480 px. Only a handful of details are open at once.
    static func detailPreviews(store: any ClipboardStore) -> ClipThumbnailStore {
        ClipThumbnailStore(
            maxCached: 8,
            maxPixel: 480,
            skipsSensitiveClips: true,
            decodePriority: nil,
            imageData: { id in await fullImageData(id, store: store) })
    }

    @MainActor
    private static func fullImageData(_ id: UUID, store: any ClipboardStore) async -> Data? {
        guard case .binary(let data, _)? = try? await store.content(for: id) else { return nil }
        return data
    }
}
