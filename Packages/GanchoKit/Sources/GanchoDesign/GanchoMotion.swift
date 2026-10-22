import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// The motion policy in one place. Five tokens: `quick` (settle) for
/// selection, focus and chip moves; `smooth` (arrive) for content that
/// appears; `leave` for content that goes; `replace` (swap) for content that
/// changes in place; `press` for a primary button. Under Reduce Motion nothing
/// travels: settle lands instantly, arrive and leave become a 100 ms fade,
/// swap is a plain swap and press keeps its colour change but drops the scale.
public enum GanchoMotion {
    /// Selection, focus and chip moves: short and settled.
    public static let quick: Animation = .snappy(duration: 0.18, extraBounce: 0)
    /// Content that swaps or appears: a touch longer, no overshoot.
    public static let smooth: Animation = .smooth(duration: 0.22)
    /// Content that goes away: brief and accelerating.
    public static let leave: Animation = .easeIn(duration: 0.14)
    /// The Reduce Motion stand-in for `smooth` and `leave`.
    public static let fade: Animation = .easeInOut(duration: 0.1)
    /// A primary button under the pointer or key: scale and duration.
    public static let pressScale: CGFloat = 0.96
    public static let press: Animation = .easeOut(duration: 0.08)

    /// nil under Reduce Motion, so a `.animation(_:value:)` scope becomes a no-op.
    nonisolated public static func animation(_ base: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }

    nonisolated public static func quick(reduceMotion: Bool) -> Animation? {
        animation(quick, reduceMotion: reduceMotion)
    }

    nonisolated public static func smooth(reduceMotion: Bool) -> Animation? {
        reduceMotion ? fade : smooth
    }

    nonisolated public static func leave(reduceMotion: Bool) -> Animation? {
        reduceMotion ? fade : leave
    }

    nonisolated public static func pressScale(reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : pressScale
    }

    /// The system setting, for code outside a view (async completions, button
    /// styles) that cannot read `accessibilityReduceMotion` from the environment.
    @MainActor public static var systemReducesMotion: Bool {
        #if canImport(AppKit)
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #elseif canImport(UIKit)
            UIAccessibility.isReduceMotionEnabled
        #else
            false
        #endif
    }

    /// Whether a content swap may blur; the pure half of `replace` so the
    /// policy is testable without building a transition.
    nonisolated public static func usesBlurReplace(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Whether arriving content may travel (move or scale); the pure half of
    /// `travel`.
    nonisolated public static func usesTravel(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Content that arrives with `insertion` and leaves on the `leave` curve;
    /// a plain fade under Reduce Motion.
    @MainActor public static func travel(
        _ insertion: AnyTransition, reduceMotion: Bool
    ) -> AnyTransition {
        usesTravel(reduceMotion: reduceMotion)
            ? .asymmetric(insertion: insertion, removal: insertion.animation(leave)) : .opacity
    }

    /// A content swap: blur-replace normally, a plain swap under Reduce Motion.
    /// Main-actor because SwiftUI's transition initializers are.
    @MainActor public static func replace(reduceMotion: Bool) -> AnyTransition {
        usesBlurReplace(reduceMotion: reduceMotion)
            ? AnyTransition(BlurReplaceTransition(configuration: .downUp)) : .identity
    }
}
