import Foundation

/// What the capture engine needs from a pasteboard, split by privacy cost.
///
/// The split is the contract that keeps the detect-before-read strategy
/// honest: `currentChangeCount()` and `currentTypes()` are metadata-only and
/// never trigger the OS pasteboard-privacy flow, while `readPayload()` is a
/// full content read that may block for seconds under the "Ask" permission
/// (measured ~2.2 s on macOS 26.5) — so it must never run on the main thread.
/// Implementations must be safe to call from any thread.
public protocol PasteboardReading: Sendable {
    /// Cheap, metadata-only. Bumps whenever any app writes the pasteboard.
    func currentChangeCount() -> Int

    /// Cheap, metadata-only. Used for the sensitive-type veto BEFORE any
    /// content is read, and for the Universal Clipboard badge.
    func currentTypes() -> Set<String>

    /// Full content read — the only call with a privacy cost. Returns the
    /// richest payload available, or nil when the pasteboard is empty or
    /// the read was denied by the OS.
    func readPayload() -> PasteboardCapture.Payload?
}
