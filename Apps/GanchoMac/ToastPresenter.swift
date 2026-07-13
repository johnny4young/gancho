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
        case suggestion
        case warning

        var symbol: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .suggestion: "sparkles"
            case .warning: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: GanchoTokens.Palette.success
            case .suggestion: GanchoTokens.Palette.accent
            case .warning: GanchoTokens.Palette.warning
            }
        }
    }

    // A resource (not a bare LocalizedStringKey) so the presenter can resolve the
    // localized string to a VoiceOver announcement, not just render it.
    let message: LocalizedStringResource
    var style: Style = .success
    /// Optional one-tap follow-up (e.g. "Enable" → open Accessibility).
    var action: ToastAction?
}

struct ToastAction {
    let title: LocalizedStringKey
    /// Accessibility id for the action button, so UI tests can target a
    /// specific action (e.g. the delete Undo). Defaults to the shared id, so
    /// every existing toast keeps its previous identifier unchanged.
    var accessibilityIdentifier: String = "toast-action"
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
                .accessibilityIdentifier(action.accessibilityIdentifier)
                .foregroundStyle(GanchoTokens.Palette.accent)
            }
        }
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.vertical, GanchoTokens.Spacing.sm)
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        // `.contain` (not `.combine`): the toast is an accessibility CONTAINER,
        // so its action button (e.g. the delete Undo, id `toast-undo`) stays a
        // separately reachable element — VoiceOver can navigate to it, and a UI
        // test can target it. `.combine` merged the button into the parent, hiding
        // it. The explicit announcement below still voices the message.
        .accessibilityElement(children: .contain)
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
                .frame(width: 360)
                // Keep width available for wrapping, but collapse the hosting
                // view's otherwise flexible height to the toast's ideal height.
                .fixedSize(horizontal: false, vertical: true))
        host.layout()
        let size = host.fittingSize

        let panel = ensurePanel()
        panel.setContentSize(size)
        panel.contentView = host
        positionTopCenter(panel, size: size)
        panel.orderFrontRegardless()

        // The toast lives in a non-activating panel VoiceOver never focuses, so a
        // blind user would otherwise get no confirmation that the action happened.
        // Speak it explicitly.
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: String(localized: toast.message),
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ])

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
        // Show on the screen the user is actually looking at — the one under the
        // pointer (where the panel was just used), then the key window's screen —
        // not always `NSScreen.main`, which on a multi-display Mac is the screen
        // with the menu bar and can be a different display entirely (the toast
        // then flashes off where the user isn't looking, reading as "no toast").
        let mouse = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSApp.keyWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - GanchoTokens.Spacing.xl))
    }
}
