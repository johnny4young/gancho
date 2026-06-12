#if os(macOS)
    import AppKit
    import Foundation
    import GanchoKit

    /// macOS capture engine — capture-spike starter; the capture-hardening
    /// pass adds adaptive backoff and the pasteboard-privacy integration.
    ///
    /// Approach (inherited from years of Maccy/community practice, MIT):
    /// poll `NSPasteboard.general.changeCount` (cheap, reads no content); read
    /// content only when the count changes; honor sensitive-type vetoes BEFORE
    /// reading anything else; mark our own writes with a private type to avoid
    /// self-capture loops.
    ///
    /// TODO: integrate `NSPasteboard.accessBehavior` checks + detect APIs
    /// before full reads once the privacy-flag matrix is documented.
    @MainActor
    public final class MacPasteboardMonitor: PasteboardObserving {
        /// Private marker type for Gancho's own pasteboard writes.
        public static let selfWriteMarker = NSPasteboard.PasteboardType(
            "com.johnny4young.gancho.self-write")

        public var onCapture: ((PasteboardCapture) -> Void)?

        /// Polling cadence. Adaptive backoff (250ms active / 1–2s idle / paused
        /// on screen lock) comes with the capture-hardening pass; the scaffold
        /// uses a fixed interval.
        public var pollInterval: Duration = .milliseconds(250)

        private var pollTask: Task<Void, Never>?
        private var lastChangeCount: Int

        public init() {
            lastChangeCount = NSPasteboard.general.changeCount
        }

        public func start() {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    self?.pollOnce()
                    let interval = self?.pollInterval ?? .milliseconds(250)
                    try? await Task.sleep(for: interval)
                }
            }
        }

        public func stop() {
            pollTask?.cancel()
            pollTask = nil
        }

        private func pollOnce() {
            let pasteboard = NSPasteboard.general
            let count = pasteboard.changeCount
            guard count != lastChangeCount else { return }
            lastChangeCount = count

            let types = Set((pasteboard.types ?? []).map(\.rawValue))
            // Never store password-manager/transient/auto-generated content,
            // and never re-capture our own writes.
            guard SensitivePasteboardTypes.captureVeto.isDisjoint(with: types),
                !types.contains(Self.selfWriteMarker.rawValue)
            else { return }

            guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
            let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            onCapture?(PasteboardCapture(text: text, sourceAppBundleID: source))
        }
    }
#endif
