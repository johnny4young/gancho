import Foundation

/// Inputs the polling policy needs about the user's presence. Abstracted so
/// the monitor's mode transitions are testable without synthesizing input
/// events or locking the screen.
public protocol UserActivitySource: Sendable {
    /// Seconds since the last hardware input event (keyboard, mouse, scroll).
    func secondsSinceLastUserInput() -> TimeInterval

    /// True while the login session's screen is locked.
    func isScreenLocked() -> Bool
}

#if os(macOS)
    import CoreGraphics
    import Synchronization

    /// Real implementation backed by Quartz event timestamps and the session
    /// dictionary. Neither call requires Accessibility or Input Monitoring
    /// permission — they expose recency and lock state, never event content.
    public struct SystemUserActivitySource: UserActivitySource {
        /// Event kinds that count as "the user is here". Polled individually
        /// because Quartz has no public "any input" sentinel in Swift.
        private static let presenceEvents: [CGEventType] = [
            .keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .scrollWheel
        ]

        public init() {}

        public func secondsSinceLastUserInput() -> TimeInterval {
            Self.presenceEvents
                .map {
                    CGEventSource.secondsSinceLastEventType(
                        .combinedSessionState, eventType: $0)
                }
                .min() ?? .infinity
        }

        public func isScreenLocked() -> Bool {
            ScreenLockState.shared.isLocked()
        }
    }

    /// The session's lock state. Reading the session dictionary is a
    /// WindowServer round trip, so an unlocked answer is reused until the lock
    /// notification arrives or `revalidateAfter` passes; a locked one is
    /// re-read on every call so an unlock is seen at once.
    final class ScreenLockState: Sendable {
        static let shared = ScreenLockState()

        private struct Cached {
            var isLocked: Bool
            var readAt: ContinuousClock.Instant
        }

        private let cached = Mutex<Cached?>(nil)
        private let observer = Mutex<(any NSObjectProtocol)?>(nil)
        private let revalidateAfter: Duration
        private let readSession: @Sendable () -> Bool

        init(
            revalidateAfter: Duration = .seconds(30),
            readSession: @escaping @Sendable () -> Bool = ScreenLockState.sessionIsLocked
        ) {
            self.revalidateAfter = revalidateAfter
            self.readSession = readSession
        }

        func isLocked(now: ContinuousClock.Instant = .now) -> Bool {
            observeLockNotifications()
            if let last = cached.withLock({ $0 }), !last.isLocked,
                now - last.readAt < revalidateAfter
            {
                return false
            }
            let isLocked = readSession()
            cached.withLock { $0 = Cached(isLocked: isLocked, readAt: now) }
            return isLocked
        }

        /// Drops the cached answer, as the lock notification does.
        func invalidate() {
            cached.withLock { $0 = nil }
        }

        private func observeLockNotifications() {
            observer.withLock { observer in
                guard observer == nil else { return }
                observer = DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name("com.apple.screenIsLocked"), object: nil,
                    queue: nil
                ) { [weak self] _ in self?.invalidate() }
            }
        }

        static func sessionIsLocked() -> Bool {
            guard
                let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            else { return false }
            return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
        }
    }
#endif
