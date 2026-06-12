import Foundation

/// Pure scheduling policy for the macOS capture poll loop. Kept free of
/// AppKit/CoreGraphics so every transition is unit-testable.
///
/// Budget rationale (validated by the capture spike): 250 ms while the user
/// is active keeps captures feeling instant; 1.5 s in idle keeps average CPU
/// well under the 0.5% budget; polling pauses entirely while the screen is
/// locked because nothing user-initiated can land on the pasteboard.
public struct AdaptivePollingPolicy: Sendable, Equatable {
    /// What the poll loop should be doing this turn.
    public enum Mode: Sendable, Equatable {
        /// User recently active — poll at `activeInterval`.
        case active
        /// No recent input — poll at `idleInterval`.
        case idle
        /// Screen locked — skip polling, re-check at `pausedProbeInterval`.
        case paused
    }

    public var activeInterval: Duration
    public var idleInterval: Duration
    /// Input older than this demotes the loop to `.idle`.
    public var idleAfter: Duration
    /// How often to re-check for unlock while `.paused`.
    public var pausedProbeInterval: Duration

    public init(
        activeInterval: Duration = .milliseconds(250),
        idleInterval: Duration = .milliseconds(1500),
        idleAfter: Duration = .seconds(30),
        pausedProbeInterval: Duration = .seconds(2)
    ) {
        self.activeInterval = activeInterval
        self.idleInterval = idleInterval
        self.idleAfter = idleAfter
        self.pausedProbeInterval = pausedProbeInterval
    }

    /// Lock always wins; otherwise recency of user input picks active vs idle.
    public func mode(
        secondsSinceLastUserInput: TimeInterval,
        isScreenLocked: Bool
    ) -> Mode {
        if isScreenLocked { return .paused }
        let idleSeconds =
            Double(idleAfter.components.seconds)
            + Double(idleAfter.components.attoseconds) * 1e-18
        return secondsSinceLastUserInput >= idleSeconds ? .idle : .active
    }

    /// Sleep length for the mode. `.paused` returns the probe cadence — the
    /// loop keeps breathing cheaply so it notices unlock without observers.
    public func interval(for mode: Mode) -> Duration {
        switch mode {
        case .active: activeInterval
        case .idle: idleInterval
        case .paused: pausedProbeInterval
        }
    }
}
