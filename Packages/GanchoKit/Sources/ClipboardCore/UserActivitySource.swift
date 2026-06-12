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

    /// Real implementation backed by Quartz event timestamps and the session
    /// dictionary. Neither call requires Accessibility or Input Monitoring
    /// permission — they expose recency and lock state, never event content.
    public struct SystemUserActivitySource: UserActivitySource {
        /// Event kinds that count as "the user is here". Polled individually
        /// because Quartz has no public "any input" sentinel in Swift.
        private static let presenceEvents: [CGEventType] = [
            .keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown,
            .otherMouseDown, .scrollWheel,
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
            guard
                let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            else { return false }
            return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
        }
    }
#endif
