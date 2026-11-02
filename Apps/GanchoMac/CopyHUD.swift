import AppKit
import GanchoDesign
import SwiftUI

/// A glanceable confirmation for something that happened at copy time, away
/// from the panel. It never takes focus and never shows clip content.
struct CopyHUD {
    let symbol: String
    let title: LocalizedStringResource
}

private struct CopyHUDView: View {
    let hud: CopyHUD

    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: hud.symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(GanchoTokens.Palette.brandText)
                .frame(width: 34, height: 34)
                .background(
                    GanchoTokens.Palette.brandTint,
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                .accessibilityHidden(true)
            Text(hud.title)
                .font(.body.weight(.bold))
                .fixedSize()
        }
        .padding(GanchoTokens.Spacing.sm)
        .padding(.trailing, GanchoTokens.Spacing.xs)
        .ganchoSurface(radius: GanchoTokens.Radius.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(hud.title))
        .accessibilityIdentifier("copy-hud")
    }
}

@MainActor
final class CopyHUDPresenter {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Shows the HUD top-center on the active screen, below a visible toast.
    func show(_ hud: CopyHUD, below toastFrame: NSRect? = nil) {
        let host = NSHostingView(
            rootView: CopyHUDView(hud: hud)
                .environment(
                    \.ganchoOpaqueSurfaces, !PanelTranslucency.isEnabled(in: defaults)))
        host.layout()
        let size = host.fittingSize
        let panel = ensurePanel()
        panel.contentView = host
        panel.setContentSize(size)
        if let screen = NSScreen.underPointer {
            let top =
                toastFrame.map { $0.minY - GanchoTokens.Spacing.xs }
                ?? screen.visibleFrame.maxY - GanchoTokens.Spacing.xl
            panel.setFrameOrigin(
                NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: top - size.height))
        }
        // Also cancels a fade-out still running from the previous HUD.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.orderFrontRegardless()
        // VoiceOver never focuses a non-activating panel.
        NSAccessibility.post(
            element: NSApp as Any, notification: .announcementRequested,
            userInfo: [
                .announcement: String(localized: hud.title),
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ])

        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// UI tests keep it up long enough to be found and rendered.
    private static var duration: Duration {
        #if DEBUG
            if CommandLine.arguments.contains("-ui-test-keep-copy-hud") { return .seconds(120) }
        #endif
        return .seconds(1.6)
    }

    func dismiss() {
        dismissTask?.cancel()
        guard let panel, panel.isVisible else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                guard panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            }
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        panel.setAccessibilityIdentifier("copy-hud-panel")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }
}
