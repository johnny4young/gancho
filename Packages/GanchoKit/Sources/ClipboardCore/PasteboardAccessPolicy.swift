import Foundation

/// Platform-neutral view of the OS pasteboard-privacy verdict for this app
/// (macOS "Paste from Other Apps": Ask / Allow / Deny).
public enum PasteboardAccessVerdict: Sendable, Equatable {
    /// Reads succeed immediately (Allow, or enforcement not active).
    case allowed
    /// Reads block until the system resolves consent (measured ~2.2 s on
    /// macOS 26.5 with the privacy preview flag; indefinite once the alert
    /// UI ships). Capture keeps running — reads are off-main already.
    case ask
    /// Reads silently return nil. Capture must pause and tell the user
    /// instead of burning retries (decision from the privacy spike).
    case denied
}

/// Injectable so monitor behavior under Deny/Ask is unit-testable without
/// touching System Settings.
public protocol PasteboardAccessPolicy: Sendable {
    func currentVerdict() -> PasteboardAccessVerdict
}

#if os(macOS)
    import AppKit

    /// Real policy over `NSPasteboard.general.accessBehavior` (macOS 15.4+).
    /// `.default` maps to `.allowed`: with enforcement dormant that is the
    /// observed behavior, and once alerts ship the system resolves consent
    /// itself — the monitor just sees an ask-like stall.
    public struct SystemPasteboardAccessPolicy: PasteboardAccessPolicy {
        public init() {}

        public func currentVerdict() -> PasteboardAccessVerdict {
            switch NSPasteboard.general.accessBehavior {
            case .alwaysDeny: .denied
            case .ask: .ask
            case .alwaysAllow, .default: .allowed
            @unknown default: .allowed
            }
        }
    }
#endif
