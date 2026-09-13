import AppKit
import GanchoAI

/// Main-actor window ownership is separate from asynchronous image work. A
/// superseded request may finish, but can neither close the new selector nor
/// restore old windows over it.
@MainActor final class ScreenTextWorkflow {
    private let selector = ScreenTextSelector()
    private var request: UUID?
    private var windows: [NSWindow]?
    private var previousApp: NSRunningApplication?
    private let capture: @Sendable (CGRect) async throws -> Data

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

    func recognize(_ id: UUID, didCapture: @MainActor () -> Void) async throws -> String? {
        defer { restore(id) }
        guard request == id else { throw CancellationError() }
        try Task.checkCancellation()
        // Do not hide windows until this task owns the cancellation cleanup.
        // Eligibility checks can suspend before recognition even begins.
        let visible = NSApp.windows.filter(\.isVisible)
        windows = visible
        for window in visible { window.orderOut(nil) }
        guard
            let region = await withTaskCancellationHandler(
                operation: {
                    await selector.select(id: id)
                }, onCancel: { Task { @MainActor [weak self] in self?.cancel(id) } })
        else { throw CancellationError() }
        try Task.checkCancellation()
        // Allow the window server to remove overlays before the one-shot
        // snapshot. This delay is not a substitute for real compositor QA.
        try await Task.sleep(for: .milliseconds(100))
        guard request == id else { throw CancellationError() }
        let data = try await capture(region)
        try Task.checkCancellation()
        restore(id)
        didCapture()
        return try await ImageTextExtractor().extractText(from: data)
    }

    private func cancel(_ id: UUID) {
        guard request == id else { return }
        cancel()
    }

    private func restore(_ id: UUID) {
        guard request == id else { return }
        request = nil
        if let windows {
            for window in windows { window.orderFrontRegardless() }
            if let previousApp, previousApp != NSRunningApplication.current {
                previousApp.activate()
            }
        }
        windows = nil
        previousApp = nil
    }
}
