import AppKit
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// A paste-stack run while the panel is closed: a small strip under the menu
/// bar with the position, the next clip and Skip / Back / Reset / End. It never
/// takes focus, so the app being pasted into stays frontmost.
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
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(.secondary)
            Text("\(stack.cursor + 1) of \(stack.count)")
                .monospacedDigit()
                .fontWeight(.semibold)
                .accessibilityIdentifier("paste-stack-run-position")
            if let next = stack.next {
                Image(systemName: next.clip.kind.symbolName)
                    .foregroundStyle(.secondary)
                Text(verbatim: title(next.clip))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200, alignment: .leading)
                    .accessibilityIdentifier("paste-stack-run-next")
            }
            Divider().frame(height: 14)
            control("Skip", symbol: "forward.end", id: "paste-stack-run-skip") {
                model.skipInStack()
            }
            control("Back", symbol: "backward.end", id: "paste-stack-run-back") {
                model.backInStack()
            }
            control("Reset", symbol: "arrow.counterclockwise", id: "paste-stack-run-reset") {
                model.resetStack()
            }
            control("End run", symbol: "xmark", id: "paste-stack-run-end") {
                model.endStackRun()
            }
        }
        .font(.callout)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
    }

    private func control(
        _ title: LocalizedStringKey, symbol: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier(id)
    }

    /// Kinds only for a secret, in Private Mode and during an unrevealed share.
    private func title(_ item: ClipItem) -> String {
        guard !model.previewsHidden, !ClipSafePresentation.requiresMasking(item) else {
            return ClipSafePresentation.masked
        }
        return item.title.isEmpty ? item.preview : item.title
    }
}
