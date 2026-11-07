import AppKit
import KeyboardShortcuts

// The native shortcut fixture compiles the gate's source file directly.
#if canImport(ClipboardCore)
    import ClipboardCore
#endif

/// Registers global shortcut actions that run once per press, on release, or
/// on the press while a menu tracks (see `ReleaseShortcutGate`).
@MainActor
final class ReleaseShortcuts {
    private var gate = ReleaseShortcutGate<KeyboardShortcuts.Name>()
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        // The same synchronous notifications KeyboardShortcuts switches to raw
        // key events on, so the gate and the dependency agree on the mode.
        let changes = [
            (NSMenu.didBeginTrackingNotification, true),
            (NSMenu.didEndTrackingNotification, false)
        ]
        for (notification, tracking) in changes {
            let observer = notificationCenter.addObserver(
                forName: notification, object: nil, queue: nil
            ) { [weak self] _ in
                guard Thread.isMainThread else {
                    Task { @MainActor [weak self] in self?.gate.setMenuTracking(tracking) }
                    return
                }
                MainActor.assumeIsolated { self?.gate.setMenuTracking(tracking) }
            }
            observers.append(observer)
        }
    }

    isolated deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    func onRelease(_ name: KeyboardShortcuts.Name, perform action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
            if self?.gate.keyDown(name) == true { action() }
        }
        KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
            if self?.gate.keyUp(name) == true { action() }
        }
    }
}
