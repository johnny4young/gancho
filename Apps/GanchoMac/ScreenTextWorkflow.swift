import AppKit
import GanchoAI
import GanchoAppCore

/// Main-actor window ownership is separate from asynchronous image work. A
/// superseded request may finish, but can neither close the new selector nor
/// restore old windows over it.
@MainActor final class ScreenTextWorkflow {
    private let selector = ScreenTextSelector()
    private var request: UUID?
    private var windows: [NSWindow]?
    private var previousApp: NSRunningApplication?
    private let capture: @Sendable (CGRect) async throws -> Data

    /// How a window hidden for the capture comes back. The default is the raw
    /// AppKit order, which is correct only for a window nothing else owns: the
    /// history panel belongs to `PanelController` and has to return through
    /// `show(model:)`, or it comes back non-key — and a window that is not key
    /// can never resign key, so its auto-hide-on-focus-loss is dead for the
    /// rest of the session and it floats above whatever the user is working
    /// in. AppModel installs the real policy once `self` exists.
    var restoreWindow: @MainActor (NSWindow) -> Void = { $0.orderFrontRegardless() }

    init(
        capture: @escaping @Sendable (CGRect) async throws -> Data = {
            try await ScreenTextCapture().image(in: $0)
        }
    ) {
        self.capture = capture
    }

    func begin(previousApp: NSRunningApplication?) -> UUID {
        cancel()
        let id = UUID()
        request = id
        self.previousApp = previousApp
        return id
    }

    func cancel() {
        guard let request else { return }
        selector.cancel(id: request)
        restore(request)
    }

    func recognize(
        _ id: UUID, isAllowed: @MainActor () -> Bool, didCapture: @MainActor () -> Void
    ) async throws -> ManualOCRResult? {
        defer { restore(id) }
        guard request == id else { throw CancellationError() }
        try Task.checkCancellation()
        // Do not hide windows until this task owns the cancellation cleanup.
        // Eligibility checks can suspend before recognition even begins.
        let visible = NSApp.windows.filter(Self.isHidable)
        windows = visible
        for window in visible { window.orderOut(nil) }
        let data = try await ScreenTextAcquisition.image(
            select: {
                await withTaskCancellationHandler(
                    operation: { await selector.select(id: id) },
                    onCancel: { Task { @MainActor [weak self] in self?.cancel(id) } })
            },
            isAllowed: { self.request == id && isAllowed() },
            capture: capture)
        restore(id)
        didCapture()
        let lines = try await ImageTextExtractor().recognizeLines(in: data)
        return ManualOCRResult(lines: lines)
    }

    /// `NSApp.windows` is everything AppKit holds for this process, not the
    /// content Gancho draws. Status-level windows are left alone on purpose:
    /// the in-process status item's `NSStatusBarWindow` lives there, and
    /// ordering it out makes the menu-bar icon disappear without tripping the
    /// affordance watchdog (which reads `statusItem.isVisible` and
    /// `button?.window != nil` — neither changes on `orderOut`), while
    /// `orderFrontRegardless()` is not how `NSStatusItem` brings it back. The
    /// toast panel sits at the same level and is already dismissed before a
    /// capture starts. The selector's own overlay is higher still.
    private static func isHidable(_ window: NSWindow) -> Bool {
        window.isVisible && window.level.rawValue < NSWindow.Level.statusBar.rawValue
    }

    private func cancel(_ id: UUID) {
        guard request == id else { return }
        cancel()
    }

    private func restore(_ id: UUID) {
        guard request == id else { return }
        request = nil
        if let windows {
            for window in windows { restoreWindow(window) }
            if let previousApp, previousApp != NSRunningApplication.current {
                previousApp.activate()
            }
        }
        windows = nil
        previousApp = nil
    }
}
