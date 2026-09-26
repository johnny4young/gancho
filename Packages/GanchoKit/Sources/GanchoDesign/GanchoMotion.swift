import SwiftUI

/// The panel's motion policy in one place: two curves, and every one of them
/// off under Reduce Motion so state changes land instantly instead of gliding.
public enum GanchoMotion {
    /// Selection, focus and chip moves: short and settled.
    public static let quick: Animation = .snappy(duration: 0.18, extraBounce: 0)
    /// Content that swaps or appears: a touch longer, no overshoot.
    public static let smooth: Animation = .smooth(duration: 0.22)

    /// nil under Reduce Motion, so a `.animation(_:value:)` scope becomes a no-op.
    nonisolated public static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }

    /// A content swap: blur-replace normally, a plain swap under Reduce Motion.
    nonisolated public static func replace(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : AnyTransition(BlurReplaceTransition(configuration: .downUp))
    }
}
