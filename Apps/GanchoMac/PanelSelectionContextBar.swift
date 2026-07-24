import GanchoDesign
import SwiftUI

/// Batch actions for the panel's visible multi-selection.
///
/// The bar receives values and effects explicitly so it stays independent from
/// `AppModel` and from the selection reducer that decides which rows are active.
struct PanelSelectionContextBar: View {
    let selectionCount: Int
    let addToStack: () -> Void
    let addToBoard: () -> Void
    let delete: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Label("\(selectionCount) clips", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(GanchoTokens.Palette.accent)
            Spacer(minLength: 0)
            Button(action: addToStack) {
                Image(systemName: "square.stack.3d.up")
            }
            .help("Add to paste stack")
            .accessibilityLabel("Add to paste stack")
            .accessibilityIdentifier("selection-add-to-stack-button")

            Button(action: addToBoard) {
                Image(systemName: "square.stack")
            }
            .help("Add to board")
            .accessibilityLabel("Add to board")
            .accessibilityIdentifier("selection-add-to-board-button")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .foregroundStyle(.red)
            .help("Delete")
            .accessibilityLabel("Delete")
            .accessibilityIdentifier("selection-delete-button")

            Divider().frame(height: 16)
            Button("Clear", action: clear)
                .accessibilityIdentifier("selection-clear-button")
        }
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
