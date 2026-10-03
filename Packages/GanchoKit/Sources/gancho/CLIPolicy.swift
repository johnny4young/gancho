import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit

/// The CLI's privacy decisions, kept free of I/O so they can be tested.
enum CLIPolicy {
    /// Why `gancho save` refuses `text`, or nil when it may be saved.
    static func saveRefusal(
        for text: String, allowSecret: Bool,
        detector: SensitiveDataDetector = SensitiveDataDetector()
    ) -> String? {
        guard !allowSecret, let category = detector.detect(text) else { return nil }
        return "gancho save: the content looks like a secret (\(category.rawValue)); "
            + "pass --allow-secret to save it anyway."
    }

    /// Why `gancho copy` refuses `item`, or nil when it may be copied. Expiry
    /// is the store's call: `content(for:)` hides exactly the rows retention
    /// will purge, while pinned, board and snippet clips stay copyable.
    static func copyRefusal(for item: ClipItem, reveal: Bool) -> String? {
        if ClipSafePresentation.requiresMasking(item), !reveal {
            return "Clip \(item.id.uuidString) is sensitive; pass --reveal to copy it."
        }
        return nil
    }

    /// Marker types stamped on the pasteboard: the self-write marker keeps the
    /// app from re-capturing the copy, and sensitive content is concealed from
    /// other clipboard managers.
    static func pasteboardMarkers(for item: ClipItem) -> [String] {
        #if os(macOS)
            var markers = [MacPasteboardMonitor.selfWriteMarker.rawValue]
        #else
            var markers: [String] = []
        #endif
        if ClipSafePresentation.requiresMasking(item) {
            markers.append(SensitivePasteboardTypes.concealed)
        }
        return markers
    }

    /// Writes `data` readable by the owner only, also when `url` already exists.
    static func writePrivately(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard fchmod(descriptor, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try handle.write(contentsOf: data)
        try handle.close()
    }
}
