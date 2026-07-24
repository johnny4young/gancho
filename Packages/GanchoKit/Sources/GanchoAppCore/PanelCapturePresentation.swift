/// The capture engine state relevant to panel presentation.
///
/// This mirrors platform monitor outcomes without importing AppKit into the
/// shared app layer. Platform shells translate their concrete monitor state at
/// the composition boundary.
public enum PanelCaptureRuntimeStatus: Sendable, Equatable {
    case stopped
    case running
    case pausedByUser
    case pausedByScreenLock
    case pausedByScreenShare
    case deniedByPrivacySettings
}

/// The single capture interruption the panel should explain.
///
/// A notice is deliberately singular: the resolver applies product precedence
/// so data-loss risk wins over operational pauses.
public enum PanelCaptureNotice: Sendable, Equatable {
    case storageEphemeral
    case privateMode
    case denied
    case screenShare
    case paused

    public var action: PanelCaptureAction? {
        switch self {
        case .privateMode: .resumePrivateMode
        case .paused: .resumeCapture
        case .denied: .openPermissionSettings
        case .storageEphemeral, .screenShare: nil
        }
    }
}

public enum PanelCaptureAction: Sendable, Equatable {
    case resumePrivateMode
    case resumeCapture
    case openPermissionSettings
}

/// Pure product policy for the panel's capture banner and footer indicator.
///
/// Keeping precedence out of SwiftUI makes combinations such as ephemeral
/// storage plus denied permission deterministic and unit-testable.
public struct PanelCapturePresentation: Sendable, Equatable {
    public let notice: PanelCaptureNotice?
    public let isCapturing: Bool

    public static func resolve(
        storageIsEphemeral: Bool,
        suppressExpectedEphemeralNotice: Bool = false,
        privateModeEnabled: Bool,
        runtimeStatus: PanelCaptureRuntimeStatus
    ) -> Self {
        let notice: PanelCaptureNotice? =
            if storageIsEphemeral, !suppressExpectedEphemeralNotice {
                .storageEphemeral
            } else if runtimeStatus == .deniedByPrivacySettings {
                .denied
            } else if privateModeEnabled {
                .privateMode
            } else if runtimeStatus == .pausedByScreenShare {
                .screenShare
            } else if runtimeStatus == .stopped {
                .paused
            } else {
                nil
            }

        return Self(
            notice: notice,
            isCapturing: runtimeStatus == .running && !privateModeEnabled)
    }
}
