import AppKit
import ClipboardCore
import GanchoAppCore

/// Couples the clipboard-history process to its menu-bar affordance.
///
/// The external helper and the in-process fallback are deliberately different
/// processes/implementations, but they share one lifetime rule: if the active
/// status-item owner disappears, Gancho terminates instead of continuing as an
/// unreachable background history recorder. Events that can take the
/// affordance away trigger the check; a slow check at rest covers the rest.
@MainActor
final class GanchoMenuBarLifecycleGuard {
    private var watchdog: MenuBarAffordanceWatchdog?
    private weak var statusItemController: StatusItemController?
    private var runningApplicationsObservation: AnyObject?
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    func monitorExternalHelper() {
        stop()
        // The list `isHelperRunning()` reads, so a helper exit is always announced.
        runningApplicationsObservation = ScreenShareDetector.observeRunningApplications {
            [weak self] in self?.watchdog?.affordanceMayHaveChanged()
        }
        startWatchdog { GanchoMenuBarHelperLauncher.isHelperRunning() }
    }

    func monitorInProcessStatusItem(_ controller: StatusItemController) {
        stop()
        statusItemController = controller
        controller.onAffordanceChange = { [weak self] in
            self?.watchdog?.affordanceMayHaveChanged()
        }
        observeMenuBarRebuilds()
        startWatchdog { [weak controller] in controller?.hasVisibleAffordance == true }
    }

    func stop() {
        watchdog?.stop()
        watchdog = nil
        runningApplicationsObservation = nil
        statusItemController?.onAffordanceChange = nil
        statusItemController = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
    }

    private func startWatchdog(isPresent: @escaping @MainActor () -> Bool) {
        let watchdog = MenuBarAffordanceWatchdog(
            isPresent: isPresent,
            onLost: { [weak self] in
                self?.stop()
                NSApplication.shared.terminate(nil)
            })
        self.watchdog = watchdog
        watchdog.start()
    }

    /// Changes that can come with the menu bar being rebuilt. Occlusion is
    /// for any app window, so the status item's own window may post it too.
    private func observeMenuBarRebuilds() {
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let events = [
            (app, NSApplication.didChangeScreenParametersNotification),
            (app, NSWindow.didChangeOcclusionStateNotification),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
            (workspace, NSWorkspace.screensDidWakeNotification)
        ]
        for (center, name) in events {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.watchdog?.affordanceMayHaveChanged() }
            }
            observers.append((center, observer))
        }
    }
}
