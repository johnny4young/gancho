import ClipboardCore
import Foundation
import GanchoAppCore
import GanchoKit

/// The menu-bar glyph's state and what the panel hides while the screen is shared.
extension AppModel {
    /// Kinds only: Private Mode, or a screen share the user hasn't revealed,
    /// whether or not capture was already paused when it started.
    var previewsHidden: Bool {
        if preferences.isPrivateModePaused { return true }
        return sharingAppName != nil && revealedScreenShareSession != screenShareSession
    }

    /// The capture state every surface names; `frontApp` only when it shows the app.
    func captureChip(frontApp: String?) -> PanelCaptureChip {
        PanelCaptureChip.resolve(
            privateModeEnabled: preferences.isPrivateModePaused,
            privateModeEndsAt: preferences.privateModeEndsAt,
            runtimeStatus: monitorStatus.panelCaptureRuntimeStatus,
            frontApp: frontApp)
    }

    /// "Show anyway" for the share in progress; the next share hides again.
    func showPreviewsWhileSharing() {
        revealedScreenShareSession = screenShareSession
    }

    var menuBarBadge: MenuBarBadge? {
        let pausedStates: Set<MonitorStatus> = [.stopped, .pausedByScreenShare, .pausedByScreenLock]
        return MenuBarBadge.resolve(
            denied: monitorStatus == .deniedByPrivacySettings,
            paused: pausedStates.contains(monitorStatus),
            privateMode: preferences.isPrivateModePaused,
            ignoresNextCopy: ignoresNextCopy,
            stackCount: pasteStackEntries.count)
    }

    /// The status item's spoken label: the capture state, plus what the badge adds.
    var menuBarAccessibilityLabel: String {
        let base = monitorStatus.menuBarLabel
        return switch menuBarBadge {
        case .ignoreNext: String(localized: "\(base), next copy ignored")
        case .stack(let count): String(localized: "\(base), \(count) waiting in the paste stack")
        case .denied, .paused, .privateMode, nil: base
        }
    }

    func refreshMenuBarClipCount() async {
        menuBarClipCount = await scopeCounts().total
    }
}
