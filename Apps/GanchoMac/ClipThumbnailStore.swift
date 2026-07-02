import Foundation
import GanchoDesign

/// The panel's thumbnail cache is the shared `GanchoDesign.ClipThumbnailStore`
/// (one implementation for both apps — A3-2.7/F-1.3); this file only bakes in
/// the macOS policy so every existing call site is unchanged.
typealias ClipThumbnailStore = GanchoDesign.ClipThumbnailStore

extension ClipThumbnailStore {
    /// The historical macOS surface: `AppModel` supplies a closure that reads
    /// a clip's raw image bytes (the `.binary` blob), or nil when the clip
    /// isn't an image / can't be read.
    ///
    /// Policy (unchanged from the pre-unification store): FIFO cap of 64,
    /// 480 px decode ceiling (the peek shows the image up to ~220 pt @2x; the
    /// 30 pt row tile just downsamples further), `.utility` decode priority,
    /// and sensitive clips ARE decoded — the peek masks them at display time
    /// (`!item.isSensitive` in `peekBody`), unlike iOS which never decodes
    /// them.
    convenience init(imageData: @escaping @MainActor (UUID) async -> Data?) {
        self.init(
            maxCached: 64,
            maxPixel: 480,
            skipsSensitiveClips: false,
            decodePriority: .utility,
            imageData: imageData)
    }
}
