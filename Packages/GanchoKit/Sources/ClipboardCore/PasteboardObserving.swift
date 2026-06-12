import Foundation
import GanchoKit

/// A captured pasteboard event, before classification/persistence.
public struct PasteboardCapture: Sendable, Equatable {
    public var text: String
    public var sourceAppBundleID: String?
    public var capturedAt: Date

    public init(text: String, sourceAppBundleID: String? = nil, capturedAt: Date = .now) {
        self.text = text
        self.sourceAppBundleID = sourceAppBundleID
        self.capturedAt = capturedAt
    }
}

/// Platform-neutral capture boundary. macOS implements automatic polling
/// (`MacPasteboardMonitor`); iOS implements intent-based capture (share
/// extension, UIPasteControl, foreground prompt) — never background reads.
/// MainActor-isolated: capture adapters live next to the UI layer and the
/// pasteboard APIs they wrap are main-thread-bound anyway.
@MainActor
public protocol PasteboardObserving: AnyObject {
    var onCapture: ((PasteboardCapture) -> Void)? { get set }
    func start()
    func stop()
}
