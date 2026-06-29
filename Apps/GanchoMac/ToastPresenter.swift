import AppKit
import GanchoDesign
import SwiftUI

/// A transient HUD shown after actions that otherwise give no feedback — paste
/// degraded to copy-only (with a one-tap "Enable" that triggers the system
/// Accessibility prompt), and pin/unpin. It floats above every app and is
/// **non-activating**: it must never steal key focus, because paste-back relies
/// on the target app keeping focus.
struct GanchoToast {
    enum Style {
        case success
        case warning

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: GanchoTokens.Palette.success
            case .warning: GanchoTokens.Palette.warning
            }
        }
    }

    let message: LocalizedStringKey
    var style: Style = .success
    /// Optional one-tap follow-up (e.g. "Enable" → open Accessibility).
    var action: ToastAction?
}

struct ToastAction {
    let title: LocalizedStringKey
    let handler: @MainActor () -> Void
}

private struct ToastView: View {
    let toast: GanchoToast
    let onDismiss: @MainActor () -> Void

    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: toast.style.symbol)
                .foregroundStyle(toast.style.tint)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if let action = toast.action {
                Button(action.title) {
                    action.handler()
                    onDismiss()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("toast-action")
                .foregroundStyle(GanchoTokens.Palette.accent)
            }
        }
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.vertical, GanchoTokens.Spacing.sm)
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gancho-toast")
    }
}

@MainActor
final class ToastPresenter {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    /// Show a toast top-center on the active screen. A new toast replaces any
    /// currently shown one and resets the auto-dismiss timer.
    func show(_ toast: GanchoToast, duration: Duration? = nil) {
        // A toast with an action (e.g. Undo) needs long enough to read AND reach
        // the button, far longer than a fire-and-forget confirmation. Callers can
        // still override; otherwise actionable toasts get 6s, plain ones 2.4s.
        let duration = duration ?? (toast.action != nil ? .seconds(6) : .seconds(2.4))
        let host = NSHostingView(
            rootView: ToastView(toast: toast, onDismiss: { [weak self] in self?.dismiss() })
                .frame(maxWidth: 360))
        host.layout()
        let size = host.fittingSize

        let panel = ensurePanel()
        panel.setContentSize(size)
        panel.contentView = host
        positionTopCenter(panel, size: size)
        panel.orderFrontRegardless()

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private func positionTopCenter(_ panel: NSPanel, size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - GanchoTokens.Spacing.xl))
    }
}
