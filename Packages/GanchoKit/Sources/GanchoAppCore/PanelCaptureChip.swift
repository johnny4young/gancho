import Foundation

/// Why capture is paused, as the footer chip names it.
public enum PanelPauseCause: Sendable, Equatable {
    case user
    case screenShare
    case screenLock
}

/// The footer's capture chip: one state, its colour family and its cause.
///
/// Storage trouble stays in the banner: an in-memory store still captures, so
/// the chip keeps describing capture itself.
public enum PanelCaptureChip: Sendable, Equatable {
    case capturing(frontApp: String?)
    /// `endsAt` is nil when Private Mode stays on until the user turns it off.
    case privateMode(endsAt: Date?)
    case paused(PanelPauseCause)
    case denied

    public static func resolve(
        privateModeEnabled: Bool,
        privateModeEndsAt: Date?,
        runtimeStatus: PanelCaptureRuntimeStatus,
        frontApp: String?
    ) -> Self {
        if runtimeStatus == .deniedByPrivacySettings { return .denied }
        if privateModeEnabled { return .privateMode(endsAt: privateModeEndsAt) }
        return switch runtimeStatus {
        case .running: .capturing(frontApp: frontApp)
        case .pausedByScreenShare: .paused(.screenShare)
        case .pausedByScreenLock: .paused(.screenLock)
        case .pausedByUser, .stopped, .deniedByPrivacySettings: .paused(.user)
        }
    }

    /// Whole minutes left, rounded up, so the chip never reads "0 min left"
    /// while Private Mode is still on.
    public static func minutesLeft(until end: Date, now: Date) -> Int {
        max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
    }
}

/// The app a paste would land in, and whether ⌘V can be posted there.
public struct PanelPasteTarget: Sendable, Equatable {
    public var appName: String?
    public var canPostPaste: Bool

    public init(appName: String? = nil, canPostPaste: Bool = true) {
        self.appName = appName
        self.canPostPaste = canPostPaste
    }

    public var label: PanelPasteLabel {
        .resolve(targetApp: appName, canPostPaste: canPostPaste)
    }
}

/// What the peek's primary button promises.
public enum PanelPasteLabel: Sendable, Equatable {
    case pasteInto(String)
    case paste
    /// Without Accessibility the paste degrades to a copy, so the button says so.
    case copy

    public static func resolve(targetApp: String?, canPostPaste: Bool) -> Self {
        guard canPostPaste else { return .copy }
        guard let targetApp, !targetApp.isEmpty else { return .paste }
        return .pasteInto(targetApp)
    }
}
