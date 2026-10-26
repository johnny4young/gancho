import Foundation

/// The Mac first run: promise, permission, shortcuts, then a live first copy
/// that ends inside the real panel.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case promise, permission, shortcuts, firstCopy

    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }

    /// The leading footer button. Only the permission step's skip moves on;
    /// every other skip closes the window.
    public var leadingAction: OnboardingAction {
        self == .permission ? .advance : .close
    }

    /// The primary footer button. Without Accessibility the permission step
    /// sends the user to System Settings instead of moving on.
    public func primaryAction(accessibilityGranted: Bool) -> OnboardingAction {
        switch self {
        case .permission where !accessibilityGranted: .openAccessibilitySettings
        case .firstCopy: .openPanel
        default: .advance
        }
    }
}

public enum OnboardingAction: Equatable, Sendable {
    case advance, close, openAccessibilitySettings, openPanel
}

public enum OnboardingCopy {
    /// "10 minutes": the configured lifetime of detected secrets, never a
    /// hard-coded default.
    public static func secretLifetime(
        _ seconds: TimeInterval, locale: Locale = .current
    )
        -> String
    {
        Duration.seconds(max(seconds, 60)).formatted(
            .units(allowed: [.hours, .minutes], width: .wide).locale(locale))
    }
}
