import Foundation
import GanchoDesign
import GanchoKit

/// The history/detail thumbnail cache is the shared
/// `GanchoDesign.ClipThumbnailStore` (one implementation for both apps); this
/// file only bakes in the iOS policy so every existing call site is unchanged.
typealias ClipThumbnailStore = GanchoDesign.ClipThumbnailStore

extension ClipThumbnailStore {
    /// The historical iOS surface: constructed straight from the store; reads
    /// the clip's `.binary` blob on demand.
    ///
    /// Policy (unchanged from the pre-unification store): FIFO cap of 64,
    /// 480 px decode ceiling (covers both the row tile and the larger detail
    /// preview on a Retina phone), default decode priority, and sensitive
    /// image clips are never decoded — they keep their masked preview.
    convenience init(store: any ClipboardStore) {
        self.init(
            maxCached: 64,
            maxPixel: 480,
            skipsSensitiveClips: true,
            decodePriority: nil,
            imageData: { id in
                guard case .binary(let data, _)? = try? await store.content(for: id) else {
                    return nil
                }
                return data
            })
    }
}
