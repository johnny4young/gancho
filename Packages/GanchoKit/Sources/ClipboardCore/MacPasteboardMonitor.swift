#if os(macOS)
    import AppKit
    import Foundation
    import GanchoKit

    /// macOS capture engine: polls `changeCount` with adaptive backoff and
    /// reads content off the main thread.
    ///
    /// Approach (inherited from years of Maccy/community practice, MIT):
    /// poll `changeCount` (cheap, reads no content); on change, run the
    /// sensitive-type veto over `types` BEFORE reading anything; only then
    /// read the payload. Our own pasteboard writes carry a private marker
    /// type so they are never re-captured.
    ///
    /// Privacy-enforcement readiness (decided by the privacy spike): the full
    /// read can block ~2.2 s under the "Ask" permission, so it runs detached
    /// from the main actor. Rapid changes coalesce: a newer change cancels the
    /// in-flight read because the pasteboard only ever exposes its latest
    /// content — delivering a stale read would mislabel it.
    @MainActor
    public final class MacPasteboardMonitor: PasteboardObserving {
        /// Private marker type for Gancho's own pasteboard writes.
        public static let selfWriteMarker = NSPasteboard.PasteboardType(
            "com.johnny4young.gancho.self-write")

        public var onCapture: ((PasteboardCapture) -> Void)?

        /// Scheduling knobs; replaceable in tests and Settings experiments.
        public var policy: AdaptivePollingPolicy

        private let reader: any PasteboardReading
        private let activity: any UserActivitySource
        private var pollTask: Task<Void, Never>?
        private var pendingRead: Task<Void, Never>?
        private var lastChangeCount: Int

        public init(
            reader: any PasteboardReading = NSPasteboardReader(),
            activity: any UserActivitySource = SystemUserActivitySource(),
            policy: AdaptivePollingPolicy = AdaptivePollingPolicy()
        ) {
            self.reader = reader
            self.activity = activity
            self.policy = policy
            // Start from the current count: history begins at launch, by design.
            lastChangeCount = reader.currentChangeCount()
        }

        public func start() {
            guard pollTask == nil else { return }
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let interval = self.tick()
                    try? await Task.sleep(for: interval)
                }
            }
        }

        public func stop() {
            pollTask?.cancel()
            pollTask = nil
            pendingRead?.cancel()
            pendingRead = nil
        }

        /// One scheduler turn: resolve the mode, poll unless paused, return
        /// how long to sleep. Internal so tests can drive turns directly.
        func tick() -> Duration {
            let mode = policy.mode(
                secondsSinceLastUserInput: activity.secondsSinceLastUserInput(),
                isScreenLocked: activity.isScreenLocked())
            if mode != .paused {
                pollOnce()
            }
            return policy.interval(for: mode)
        }

        /// Detect → veto → schedule the off-main read. Internal for tests.
        func pollOnce() {
            let count = reader.currentChangeCount()
            guard count != lastChangeCount else { return }
            lastChangeCount = count

            let types = reader.currentTypes()
            // Never store password-manager/transient/auto-generated content,
            // and never re-capture our own writes. Runs BEFORE any read.
            guard SensitivePasteboardTypes.captureVeto.isDisjoint(with: types),
                !types.contains(Self.selfWriteMarker.rawValue)
            else { return }

            scheduleRead(
                isFromUniversalClipboard: types.contains(
                    SensitivePasteboardTypes.remoteClipboard),
                sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        }

        /// Replaces any in-flight read: the pasteboard only exposes its latest
        /// content, so an unfinished read for a superseded change would return
        /// the NEW bytes under the OLD change's metadata. Coalescing also caps
        /// memory under copy bursts (no read-task chain can build up).
        private func scheduleRead(isFromUniversalClipboard: Bool, sourceAppBundleID: String?) {
            pendingRead?.cancel()
            let reader = self.reader
            pendingRead = Task { [weak self] in
                let payload = await Self.readDetached(reader)
                guard !Task.isCancelled, let payload else { return }
                self?.onCapture?(
                    PasteboardCapture(
                        payload: payload,
                        sourceAppBundleID: sourceAppBundleID,
                        isFromUniversalClipboard: isFromUniversalClipboard))
            }
        }

        /// The only content read, off the main actor (it may block under the
        /// "Ask" pasteboard permission). Cancellation is checked before the
        /// read starts; a read already in flight runs to completion but its
        /// result is dropped by the caller's cancellation guard.
        private nonisolated static func readDetached(
            _ reader: any PasteboardReading
        ) async -> PasteboardCapture.Payload? {
            await Task.detached(priority: .utility) {
                guard !Task.isCancelled else { return nil }
                return reader.readPayload()
            }.value
        }
    }
#endif
