import AppKit
import GanchoDesign
import GanchoKit
import SwiftUI

/// A glanceable note about something that happened at copy time, away from
/// the panel, with up to a few actions. It never takes focus.
struct CopyHUD {
    enum Tile {
        case symbol(String, danger: Bool = false)
        case swatch(ColorValue)
    }

    let tile: Tile
    let title: LocalizedStringResource
    var actions: [CopyHUDAction] = []
}

struct CopyHUDAction: Identifiable {
    /// Suffix of the button's accessibility identifier.
    let id: String
    let title: LocalizedStringResource
    var isPrimary = false
    let run: @MainActor () -> Void
}

private struct CopyHUDView: View {
    let hud: CopyHUD
    let perform: (CopyHUDAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.sm) {
            tile
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                Text(hud.title)
                    .font(.body.weight(.bold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320, minHeight: 34, alignment: .leading)
                    .accessibilityLabel(Text(hud.title))
                    .accessibilityIdentifier("copy-hud")
                if !hud.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(hud.actions) { action in
                            Button(String(localized: action.title)) { perform(action) }
                                .ganchoButtonStyle(action.isPrimary ? .primary : .secondary)
                                .fixedSize()
                                .accessibilityIdentifier("copy-hud-action-\(action.id)")
                        }
                    }
                }
            }
        }
        .padding(GanchoTokens.Spacing.sm)
        .padding(.trailing, GanchoTokens.Spacing.xs)
        .ganchoSurface(radius: GanchoTokens.Radius.lg)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        switch hud.tile {
        case .symbol(let name, let danger):
            Image(systemName: name)
                .font(.title3.weight(.medium))
                .foregroundStyle(
                    danger
                        ? AnyShapeStyle(
                            ReadableInk(base: GanchoTokens.Palette.danger, onWash: 0.15))
                        : AnyShapeStyle(GanchoTokens.Palette.brandText)
                )
                .frame(width: 34, height: 34)
                .background(
                    danger
                        ? AnyShapeStyle(GanchoTokens.Palette.danger.opacity(0.15))
                        : AnyShapeStyle(GanchoTokens.Palette.brandTint),
                    in: shape
                )
                .accessibilityHidden(true)
        case .swatch(let color):
            shape
                .fill(
                    Color(
                        red: Double(color.red) / 255, green: Double(color.green) / 255,
                        blue: Double(color.blue) / 255)
                )
                .overlay(shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)
        }
    }
}

/// Tracks the pointer even while Gancho is in the background, and takes the
/// first click, so the HUD's buttons work without activating the app.
private final class CopyHUDHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CopyHUDPresenter {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    /// False hides a visible HUD at once (Private Mode, a screen share).
    var isAllowed: @MainActor () -> Bool = { true }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Shows the HUD top-center on the active screen, below a visible toast.
    /// One with actions stays longer and holds while the pointer is over it.
    func show(_ hud: CopyHUD, below toastFrame: NSRect? = nil) {
        let host = CopyHUDHostingView(
            rootView: AnyView(
                CopyHUDView(hud: hud) { [weak self] action in
                    self?.dismiss()
                    action.run()
                }
                .environment(\.ganchoOpaqueSurfaces, !PanelTranslucency.isEnabled(in: defaults))))
        let duration = Self.duration(hasActions: !hud.actions.isEmpty)
        host.onHover = { [weak self] inside in
            if inside {
                self?.dismissTask?.cancel()
            } else {
                self?.scheduleDismiss(after: duration)
            }
        }
        host.layout()
        let size = host.fittingSize
        let panel = ensurePanel()
        panel.contentView = host
        panel.ignoresMouseEvents = hud.actions.isEmpty
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
        scheduleDismiss(after: duration)
        watchWhileVisible()
    }

    /// The HUD can hold on hover, so it re-checks while it shows.
    private func watchWhileVisible() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let panel = self.panel, panel.isVisible else { return }
                guard self.isAllowed() else {
                    self.dismissTask?.cancel()
                    panel.orderOut(nil)
                    return
                }
            }
        }
    }

    private func scheduleDismiss(after duration: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// UI tests keep it up long enough to be found and rendered.
    private static func duration(hasActions: Bool) -> Duration {
        #if DEBUG
            if CommandLine.arguments.contains("-ui-test-keep-copy-hud") { return .seconds(120) }
        #endif
        return hasActions ? .seconds(4) : .seconds(1.6)
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
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }
}
