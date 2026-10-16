import GanchoDesign
import SwiftUI

/// Batch actions for the panel's visible multi-selection.
///
/// The bar receives values and effects explicitly so it stays independent from
/// `AppModel` and from the selection reducer that decides which rows are active.
struct PanelSelectionContextBar: View {
    let selectionCount: Int
    let copyCombined: () -> Void
    let prepareAIContext: () -> Void
    let addToStack: () -> Void
    let addToBoard: () -> Void
    let delete: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Label("\(selectionCount) clips", systemImage: "checkmark.circle.fill")
                .panelFont(.caption, .semibold)
                .monospacedDigit()
                .foregroundStyle(GanchoTokens.Palette.accent)
            Spacer(minLength: 0)
            IconActionButton(
                "Copy combined…", systemImage: "doc.on.doc",
                identifier: "selection-copy-combined-button", action: copyCombined)
            IconActionButton(
                "Prepare context for AI…", systemImage: "text.document",
                identifier: "selection-ai-context-button", action: prepareAIContext)
            IconActionButton(
                "Add to paste stack", systemImage: "square.stack.3d.up",
                identifier: "selection-add-to-stack-button", action: addToStack)
            IconActionButton(
                "Add to board", systemImage: "square.stack",
                identifier: "selection-add-to-board-button", action: addToBoard)
            IconActionButton(
                "Delete", systemImage: "trash", identifier: "selection-delete-button",
                role: .destructive, action: delete
            )
            .foregroundStyle(GanchoTokens.Palette.danger)

            Divider().frame(height: 16)
            Button("Clear selection", action: clear)
                .accessibilityIdentifier("selection-clear-button")
        }
        .panelFont(.callout)
        .buttonStyle(.plain)
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xxs)
        .background(
            GanchoTokens.Palette.accent.opacity(0.08),
            in: RoundedRectangle(
                cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        )
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(selectionCount) clips"))
        .accessibilityIdentifier("selection-context-bar")
    }
}
