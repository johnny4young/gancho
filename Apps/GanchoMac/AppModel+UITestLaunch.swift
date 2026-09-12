import AppKit
import Foundation

/// The launch-time UI-test hooks that open a window directly, kept out of the
/// composition root beside the fixtures in `AppModel+UITestSeeds`. Each one
/// independently requires its own `-open-*-on-launch` argument, so a normal
/// launch runs none of them and presents whatever `LaunchPresentation` decided.
extension AppModel {
    /// UI-test hook: deterministic panel access without the global hotkey.
    ///
    /// The panel opens from `didFinishLaunching` and again a beat later, because
    /// the first show can land before the app is frontmost, with a one-second
    /// fallback for a runner that never posts the notification. Every path waits
    /// for the durable seeds first, so the panel renders a known list.
    func showPanelOnLaunchForUITest(afterSeeds seeds: [Task<Void, Never>]) {
        NSApplication.shared.setActivationPolicy(.regular)
        uiTestPanelObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for task in seeds { await task.value }
                guard !uiTestPanelHasOpened else { return }
                uiTestPanelHasOpened = true
                panel.show(model: self)
                _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
                try? await Task.sleep(for: .milliseconds(250))
                guard panel.isVisible else { return }
                panel.show(model: self)
                _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            }
        }
        Task { @MainActor in
            for task in seeds { await task.value }
            try? await Task.sleep(for: .seconds(1))
            // A late launch fallback must not reopen a panel the user already
            // dismissed, for example while moving into the Library.
            guard !uiTestPanelHasOpened else { return }
            uiTestPanelHasOpened = true
            panel.show(model: self)
            _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
        }
    }

    /// UI-test hooks that open a settings-style window directly, without
    /// depending on the status-item menu (which self-skips on headless runners).
    func openUITestWindowsIfRequested(afterSeeds seeds: [Task<Void, Never>]) {
        // Pairs with `-force-ephemeral-store` to assert the diagnostics
        // "Recent issues" log.
        if CommandLine.arguments.contains("-open-privacy-center-on-launch") {
            NSApplication.shared.setActivationPolicy(.regular)
            Task { @MainActor in
                // Wait for the durable seeds (incl. the private-activity-receipt
                // fixture) before opening the Privacy Center. The non-receipt
                // seeds are no-ops when their launch args are absent.
                for task in seeds { await task.value }
                try? await Task.sleep(for: .milliseconds(300))
                privacyCenterWindow.show(model: self)
                _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            }
        }
        if CommandLine.arguments.contains("-open-mcp-access-on-launch") {
            NSApplication.shared.setActivationPolicy(.regular)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                await refreshBoards()
                mcpAccessWindow.show(model: self)
                _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
            }
        }
    }
}
