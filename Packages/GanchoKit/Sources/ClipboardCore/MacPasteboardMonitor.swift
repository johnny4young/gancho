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
    /// What the monitor is doing right now — surfaced so Settings and the
    /// Privacy Center can tell the user WHY capture is not running.
    public enum MonitorStatus: Sendable, Equatable {
        case stopped
        case running
        /// Private mode — user-requested pause (`CapturePreferences`).
        case pausedByUser
        /// Screen locked; resumes alone on unlock.
        case pausedByScreenLock
        /// OS pasteboard permission is Deny: reads return nil, so polling
        /// would burn CPU for nothing. The user must change the permission
        /// in System Settings (deep-linked from the Privacy Center).
        case deniedByPrivacySettings
    }

    @MainActor
    public final class MacPasteboardMonitor: PasteboardObserving {
        /// Private marker type for Gancho's own pasteboard writes.
        public static let selfWriteMarker = NSPasteboard.PasteboardType(
            "com.johnny4young.gancho.self-write")

        public var onCapture: ((PasteboardCapture) -> Void)?

        /// Scheduling knobs; replaceable in tests and Settings experiments.
        public var policy: AdaptivePollingPolicy

        /// User capture knobs. Entering private mode pauses; leaving it
        /// resynchronizes so nothing copied while paused is captured.
        public var preferences: CapturePreferences {
            didSet {
                guard preferences.isPrivateModePaused != oldValue.isPrivateModePaused else {
                    return
                }
                if !preferences.isPrivateModePaused {
                    discardChangesWhilePaused()
                }
            }
        }

        public private(set) var status: MonitorStatus = .stopped

        private let reader: any PasteboardReading
        private let activity: any UserActivitySource
        private let accessPolicy: any PasteboardAccessPolicy
        private var pollTask: Task<Void, Never>?
        private var pendingRead: Task<Void, Never>?
        private var lastChangeCount: Int
        /// True while paused (lock or private mode); the first turn after
        /// resuming discards whatever happened to the pasteboard meanwhile.
        private var wasPaused = false

        public init(
            reader: any PasteboardReading = NSPasteboardReader(),
            activity: any UserActivitySource = SystemUserActivitySource(),
            accessPolicy: any PasteboardAccessPolicy = SystemPasteboardAccessPolicy(),
            policy: AdaptivePollingPolicy = AdaptivePollingPolicy(),
            preferences: CapturePreferences = CapturePreferences()
        ) {
            self.reader = reader
            self.activity = activity
            self.accessPolicy = accessPolicy
            self.policy = policy
            self.preferences = preferences
            // Start from the current count: history begins at launch, by design.
            lastChangeCount = reader.currentChangeCount()
        }

        public func start() {
            guard pollTask == nil else { return }
            // Privacy-spike decision: under Deny, reads return nil silently —
            // do not poll, surface the state instead.
            guard accessPolicy.currentVerdict() != .denied else {
                status = .deniedByPrivacySettings
                return
            }
            status = .running
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
            status = .stopped
        }

        /// Re-evaluates the OS pasteboard permission (e.g. after the user
        /// visits System Settings from the Privacy Center) and starts or
        /// stops accordingly.
        public func recheckAccess() {
            let verdict = accessPolicy.currentVerdict()
            if verdict == .denied {
                stop()
                status = .deniedByPrivacySettings
            } else if pollTask == nil {
                start()
            }
        }

        /// One scheduler turn: resolve the mode, poll unless paused, return
        /// how long to sleep. Internal so tests can drive turns directly.
        func tick() -> Duration {
            let mode = policy.mode(
                secondsSinceLastUserInput: activity.secondsSinceLastUserInput(),
                isScreenLocked: activity.isScreenLocked())

            if preferences.isPrivateModePaused {
                status = .pausedByUser
                wasPaused = true
                return policy.interval(for: .paused)
            }
            if mode == .paused {
                status = .pausedByScreenLock
                wasPaused = true
                return policy.interval(for: .paused)
            }

            if wasPaused {
                // Privacy rule: whatever landed on the pasteboard while we
                // were paused is NOT history. Resync without reading.
                discardChangesWhilePaused()
            }
            status = .running
            pollOnce()
            return policy.interval(for: mode)
        }

        /// Detect → veto → preference filter → schedule the off-main read.
        /// Internal for tests.
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

            // Preference pre-filter: image-only / file-only changes the user
            // opted out of are skipped before any content read.
            let hasText = types.contains("public.utf8-plain-text")
            let isImageOnly =
                !hasText && !types.isDisjoint(with: ["public.png", "public.tiff"])
            let isFileOnly = !hasText && types.contains("public.file-url")
            if (isImageOnly && !preferences.captureImages)
                || (isFileOnly && !preferences.captureFileReferences)
            {
                return
            }

            scheduleRead(
                isFromUniversalClipboard: types.contains(
                    SensitivePasteboardTypes.remoteClipboard),
                sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        }

        /// Forgets pasteboard changes that happened while capture was paused
        /// (private mode or screen lock) — metadata-only, nothing is read.
        private func discardChangesWhilePaused() {
            lastChangeCount = reader.currentChangeCount()
            wasPaused = false
        }

        /// Replaces any in-flight read: the pasteboard only exposes its latest
        /// content, so an unfinished read for a superseded change would return
        /// the NEW bytes under the OLD change's metadata. Coalescing also caps
        /// memory under copy bursts (no read-task chain can build up).
        private func scheduleRead(isFromUniversalClipboard: Bool, sourceAppBundleID: String?) {
            pendingRead?.cancel()
            let reader = self.reader
            let preferences = self.preferences
            pendingRead = Task { [weak self] in
                let payload = await Self.readDetached(reader)
                guard !Task.isCancelled, let payload,
                    let filtered = Self.apply(preferences, to: payload)
                else { return }
                self?.onCapture?(
                    PasteboardCapture(
                        payload: filtered,
                        sourceAppBundleID: sourceAppBundleID,
                        isFromUniversalClipboard: isFromUniversalClipboard))
            }
        }

        /// Post-read safety net for mixed-representation items: drops or
        /// degrades payloads the preferences exclude (rich text falls back
        /// to its plain companion rather than disappearing).
        static func apply(
            _ preferences: CapturePreferences, to payload: PasteboardCapture.Payload
        ) -> PasteboardCapture.Payload? {
            switch payload {
            case .image where !preferences.captureImages:
                return nil
            case .fileReferences where !preferences.captureFileReferences:
                return nil
            case .richText(_, let plain) where !preferences.captureRichText:
                guard let plain, !plain.isEmpty else { return nil }
                return .text(plain)
            case .html(_, let plain) where !preferences.captureRichText:
                guard let plain, !plain.isEmpty else { return nil }
                return .text(plain)
            default:
                return payload
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
