import AppKit
import GanchoDesign
import GanchoKit
import SwiftUI

/// A glanceable note about something that happened at copy time, away from
/// the panel, with up to a few actions. It never takes focus.
struct CopyHUD {
    enum Tile {
        case symbol(String, danger: Bool = false)
        /// The clip's own tile: its swatch, thumbnail or kind glyph.
        case clip(ClipItem, previewsHidden: Bool)
    }

    let tile: Tile
    /// What is announced, and shown unless `content` replaces it.
    let title: LocalizedStringResource
    /// A mono caps line over the title: where the clip came from.
    var caption: String?
    /// The clip's headline, shown in mono in place of the title.
    var content: String?
    var detail: String?
    /// The title's accessibility identifier.
    var identifier = "copy-hud"
    var actions: [CopyHUDAction] = []
}

struct CopyHUDAction: Identifiable {
    /// Suffix of the button's accessibility identifier.
    let id: String
    let title: LocalizedStringResource
    var isPrimary = false
    var isDestructive = false
    let run: @MainActor () -> Void
}

private struct CopyHUDView: View {
    static let tileSide: CGFloat = 34

    let hud: CopyHUD
    let perform: (CopyHUDAction) -> Void

    var body: some View {
        HStack(alignment: hud.actions.isEmpty ? .center : .top, spacing: GanchoTokens.Spacing.sm) {
            tile
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                VStack(alignment: .leading, spacing: 3) {
                    if let caption = hud.caption {
                        Text(verbatim: caption).ganchoCaps(size: 9).lineLimit(1)
                    }
                    headline
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel(Text(hud.title))
                        .accessibilityIdentifier(hud.identifier)
                    if let detail = hud.detail {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityIdentifier("\(hud.identifier)-detail")
                    }
                }
                .frame(maxWidth: 320, minHeight: Self.tileSide, alignment: .leading)
                if !hud.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(hud.actions) { action in
                            Button(String(localized: action.title)) { perform(action) }
                                .ganchoButtonStyle(style(for: action))
                                .fixedSize()
                                .accessibilityIdentifier("copy-hud-action-\(action.id)")
                        }
                    }
                }
            }
            Image(nsImage: MenuBarGlyph.hookImage(badged: false))
                .renderingMode(.template)
                .foregroundStyle(GanchoTokens.Palette.ink)
                .frame(height: Self.tileSide)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .padding(.leading, 14)
        .padding(.trailing, 18)
        // A capsule while it is one line tall.
        .ganchoSurface(radius: hud.actions.isEmpty ? 30 : GanchoTokens.Radius.xl)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var headline: some View {
        if let content = hud.content {
            Text(verbatim: content).font(GanchoType.font(.data, size: 14))
        } else {
            Text(hud.title).font(.body.weight(.semibold))
        }
    }

    private func style(for action: CopyHUDAction) -> GanchoButtonRole {
        action.isDestructive ? .destructive : action.isPrimary ? .primary : .secondary
    }

    @ViewBuilder private var tile: some View {
        switch hud.tile {
        case .symbol(let name, let danger):
            let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
            Image(systemName: name)
                .font(.title3.weight(.medium))
                .foregroundStyle(
                    danger
                        ? AnyShapeStyle(
                            ReadableInk(base: GanchoTokens.Palette.danger, onWash: 0.15))
                        : AnyShapeStyle(GanchoTokens.Palette.ink2)
                )
                .frame(width: Self.tileSide, height: Self.tileSide)
                .background(
                    danger
                        ? AnyShapeStyle(GanchoTokens.Palette.danger.opacity(0.15))
                        : AnyShapeStyle(GanchoTokens.Palette.controlFill),
                    in: shape
                )
                .accessibilityHidden(true)
        case .clip(let item, let previewsHidden):
            ClipTile(item: item, size: Self.tileSide, previewsHidden: previewsHidden)
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
        // Checked before the first frame, not only by the watch that follows.
        guard isAllowed() else { return }
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
        // Dark in both appearances: it floats over other apps' windows.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }
}
