import AppKit

/// Couples the clipboard-history process to its menu-bar affordance.
///
/// The external helper and the in-process fallback are deliberately different
/// processes/implementations, but they share one lifetime rule: if the active
/// status-item owner disappears, Gancho terminates instead of continuing as an
/// unreachable background history recorder.
@MainActor
final class GanchoMenuBarLifecycleGuard: NSObject {
    private enum Owner {
        case none
        case externalHelper
        case inProcessStatusItem
    }

    private weak var statusItemController: StatusItemController?
    private var owner = Owner.none
    private var watchdog: Timer?

    func monitorExternalHelper() {
        statusItemController = nil
        owner = .externalHelper
        startWatchdog()
    }

    func monitorInProcessStatusItem(_ controller: StatusItemController) {
        statusItemController = controller
        owner = .inProcessStatusItem
        startWatchdog()
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        statusItemController = nil
        owner = .none
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        let watchdog = Timer(
            timeInterval: 0.75,
            target: self,
            selector: #selector(verifyAffordance),
            userInfo: nil,
            repeats: true)
        self.watchdog = watchdog
        RunLoop.main.add(watchdog, forMode: .common)
    }

    @objc private func verifyAffordance() {
        let isPresent =
            switch owner {
            case .none:
                true
            case .externalHelper:
                GanchoMenuBarHelperLauncher.isHelperRunning()
            case .inProcessStatusItem:
                statusItemController?.hasVisibleAffordance == true
            }

        guard !isPresent else { return }
        stop()
        NSApplication.shared.terminate(nil)
    }
}
