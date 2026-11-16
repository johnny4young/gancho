import GanchoAppCore
import GanchoDesign
import SwiftUI

/// The paste stack's footer entry: "Stack 2", or "Stack 2 of 4" during a run.
/// It opens and closes the stack in the peek.
struct PasteStackStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isOpen: Bool

    var body: some View {
        if !model.pasteStackEntries.isEmpty {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up")
                    Text("Stack")
                    countLabel
                        .panelFont(.caption2, .medium, design: .monospaced)
                        .contentTransition(.numericText(value: Double(stack.cursor)))
                        .animation(
                            GanchoMotion.quick(reduceMotion: reduceMotion), value: stack.cursor)
                }
                .panelFont(.caption2, isOpen ? .semibold : .regular)
                .foregroundStyle(isOpen ? GanchoTokens.Palette.ink : GanchoTokens.Palette.ink2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Paste stack — click to reorder or paste in order")
            .accessibilityIdentifier("paste-stack-strip")
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        }
    }

    private var stack: PasteStack { model.pasteStack }

    /// "3 of 5" during a run, otherwise how many wait.
    private var countLabel: Text {
        stack.isRunActive
            ? Text("\(stack.cursor + 1) of \(stack.count)") : Text("\(stack.count)")
    }

    private var accessibilityLabel: Text {
        stack.isRunActive
            ? Text("Paste stack, \(stack.cursor + 1) of \(stack.count)")
            : Text("Paste stack, \(stack.count) items")
    }
}
