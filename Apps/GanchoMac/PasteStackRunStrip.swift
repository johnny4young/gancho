import AppKit
import GanchoAppCore
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

/// A paste-stack run while the panel is closed: a small strip under the menu
/// bar with the position, the next clip and Skip / Back / Reset / End run. It
/// never takes focus, so the app being pasted into stays frontmost.
@MainActor
final class PasteStackRunStripController {
    private var panel: NSPanel?

    /// Shows the strip during a run with the panel closed; hides it otherwise.
    func update(model: AppModel) {
        guard model.pasteStack.isRunActive, !model.panel.isVisible else {
            panel?.orderOut(nil)
            return
        }
        let panel = ensurePanel(model: model)
        let size = panel.contentView?.fittingSize ?? .zero
        panel.setContentSize(size)
        if let screen = NSScreen.underPointer {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: visible.maxX - size.width - GanchoTokens.Spacing.sm,
                    y: visible.maxY - size.height - GanchoTokens.Spacing.xs))
        }
        panel.orderFrontRegardless()
    }

    private func ensurePanel(model: AppModel) -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        panel.setAccessibilityIdentifier("paste-stack-run-strip")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(
            rootView: PasteStackRunStripView().environment(model).fixedSize())
        self.panel = panel
        return panel
    }
}

private struct PasteStackRunStripView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stack = model.pasteStack
        let verbs = PasteStackPresentation(stack: stack).dock(
            skipKey: KeyboardShortcuts.getShortcut(for: .pasteStackSkip)?.description,
            backKey: KeyboardShortcuts.getShortcut(for: .pasteStackBack)?.description)
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Text("\(stack.cursor + 1) of \(stack.count)")
                .panelFont(size: 12, .semibold, design: .monospaced)
                .foregroundStyle(GanchoTokens.Palette.ink)
                .accessibilityIdentifier("paste-stack-run-position")
            if let next = stack.next {
                Text(verbatim: title(next.clip))
                    .panelFont(size: 12.5)
                    .foregroundStyle(GanchoTokens.Palette.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200, alignment: .leading)
                    .accessibilityIdentifier("paste-stack-run-next")
                // The global key pastes it here; Return belongs to the app in front.
                if let key = KeyboardShortcuts.getShortcut(for: .pasteFromStack)?.description {
                    KeyCap(key).accessibilityHidden(true)
                }
            }
            Divider().frame(height: 14)
            ForEach(verbs.filter { $0.verb != .pasteNext }, id: \.verb) { verb in
                control(verb)
            }
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .background(.regularMaterial, in: shape)
        .overlay(
            shape.strokeBorder(
                GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline))
    }

    private func control(_ verb: PasteStackPresentation.DockVerb) -> some View {
        Button {
            switch verb.verb {
            case .pasteNext: model.pasteNextFromStack()
            case .skip: model.skipInStack()
            case .back: model.backInStack()
            case .reset: model.resetStack()
            case .end: model.endStackRun()
            }
        } label: {
            HStack(spacing: 5) {
                Text(title(verb.verb)).panelFont(size: 12.5, .medium).lineLimit(1)
                // esc is the open panel's key, not this strip's.
                if verb.verb != .end, let key = verb.key {
                    KeyCap(key).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 22)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(GanchoTokens.Palette.ink2)
        .disabled(!verb.isEnabled)
        .opacity(verb.isEnabled ? 1 : 0.4)
        .accessibilityIdentifier(
            "paste-stack-run-\(verb.verb == .end ? "end" : verb.verb.rawValue)")
    }

    private func title(_ verb: PasteStackPresentation.Verb) -> LocalizedStringKey {
        switch verb {
        case .pasteNext: "Paste next"
        case .skip: "Skip"
        case .back: "Back"
        case .reset: "Reset"
        case .end: "End run"
        }
    }

    /// Kinds only for a secret, in Private Mode and during an unrevealed share.
    private func title(_ item: ClipItem) -> String {
        guard !model.previewsHidden, !ClipSafePresentation.requiresMasking(item) else {
            return ClipSafePresentation.masked
        }
        return item.title.isEmpty ? item.preview : item.title
    }
}
