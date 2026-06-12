import Foundation
import GanchoKit

/// A captured pasteboard event, before classification/persistence.
/// Codable so intent-based capture surfaces (the iOS share extension) can
/// hand captures to the host app through the App Group inbox.
public struct PasteboardCapture: Sendable, Equatable, Codable {
    /// The richest representation the capture engine could read. One payload
    /// per capture: the engine picks by fidelity (files > image > rich text >
    /// HTML > plain text), keeping a plain-text companion when one exists so
    /// classification and search never depend on the rich format.
    public enum Payload: Sendable, Equatable, Codable {
        case text(String)
        case richText(rtf: Data, plainText: String?)
        case html(source: String, plainText: String?)
        /// `typeIdentifier` is the UTI the bytes were read as (png or tiff).
        case image(data: Data, typeIdentifier: String)
        case fileReferences([URL])
    }

    public var payload: Payload
    public var sourceAppBundleID: String?
    /// True when the item arrived via Universal Clipboard / Handoff. Shown as
    /// a badge; sync uses it to avoid duplicating already-synced items.
    public var isFromUniversalClipboard: Bool
    public var capturedAt: Date

    public init(
        payload: Payload,
        sourceAppBundleID: String? = nil,
        isFromUniversalClipboard: Bool = false,
        capturedAt: Date = .now
    ) {
        self.payload = payload
        self.sourceAppBundleID = sourceAppBundleID
        self.isFromUniversalClipboard = isFromUniversalClipboard
        self.capturedAt = capturedAt
    }

    /// Convenience for plain-text captures (the iOS intent-based adapters).
    public init(text: String, sourceAppBundleID: String? = nil, capturedAt: Date = .now) {
        self.init(
            payload: .text(text), sourceAppBundleID: sourceAppBundleID, capturedAt: capturedAt)
    }

    /// Best plain-text rendering of the payload, when one exists. Image and
    /// file payloads return nil — callers decide their own preview strategy.
    public var textRepresentation: String? {
        switch payload {
        case .text(let string): string
        case .richText(_, let plain): plain
        case .html(let source, let plain): plain ?? source
        case .image, .fileReferences: nil
        }
    }
}

/// Platform-neutral capture boundary. macOS implements automatic polling
/// (`MacPasteboardMonitor`); iOS implements intent-based capture (share
/// extension, UIPasteControl, foreground prompt) — never background reads.
/// MainActor-isolated: capture adapters live next to the UI layer and
/// deliver into UI state.
@MainActor
public protocol PasteboardObserving: AnyObject {
    var onCapture: ((PasteboardCapture) -> Void)? { get set }
    func start()
    func stop()
}
