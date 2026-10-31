import GanchoAppCore
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

/// The paste queue made visible. `AppModel`'s paste stack already worked, but it
/// only lived behind a context menu — a hidden power feature. This footer strip
/// surfaces it: a compact row when the queue is non-empty, a popover to
/// reorder / remove / paste. The queue is session-local and never syncs.
///
/// Iterates over queue *entries* (each with a stable id independent of the
/// clip), so the same clip enqueued twice never collides as a SwiftUI list
/// identity and "remove this one" removes exactly one.
struct PasteStackStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showQueue = false

    var body: some View {
        if !model.pasteStackEntries.isEmpty {
            Button {
                showQueue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                    countLabel
                        .panelFont(.caption2, .semibold)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(stack.cursor)))
                        .animation(
                            GanchoMotion.quick(reduceMotion: reduceMotion), value: stack.cursor)
                    ForEach(stack.entries.dropFirst(stack.cursor).prefix(3)) { entry in
                        Image(systemName: entry.clip.kind.symbolName)
                            .panelFont(size: 9)
                            .foregroundStyle(.secondary)
                    }
                    if stack.remaining > 3 {
                        Text("+\(stack.remaining - 3)")
                            .panelFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.fill.tertiary, in: .capsule)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Paste stack — click to reorder or paste in order")
            .accessibilityIdentifier("paste-stack-strip")
            .accessibilityLabel(accessibilityLabel)
            .popover(isPresented: $showQueue, arrowEdge: .top) {
                queuePopover
            }
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

    private var queuePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Paste stack").panelFont(.headline)
                if stack.isRunActive {
                    countLabel.panelFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let shortcut = KeyboardShortcuts.getShortcut(for: .pasteFromStack) {
                    Text(verbatim: "\(shortcut)")
                        .panelFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary)
                }
            }

            List {
                ForEach(Array(model.pasteStackEntries.enumerated()), id: \.element.id) {
                    index, entry in
                    queueRow(entry, index: index)
                }
                .onMove { source, destination in
                    model.moveInStack(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .frame(height: 200)
            .accessibilityIdentifier("paste-stack-queue")

            HStack(spacing: 8) {
                Button("Paste next") {
                    model.pasteNextFromStack()
                    if model.pasteStackEntries.isEmpty { showQueue = false }
                }
                .disabled(stack.next == nil)
                .accessibilityIdentifier("paste-stack-next")
                Button("Skip") { model.skipInStack() }
                    .disabled(stack.next == nil)
                    .accessibilityIdentifier("paste-stack-skip")
                Button("Back") { model.backInStack() }
                    .disabled(stack.cursor == 0)
                    .accessibilityIdentifier("paste-stack-back")
                Button("Reset") { model.resetStack() }
                    .disabled(stack.cursor == 0)
                    .accessibilityIdentifier("paste-stack-reset")
                Spacer()
                Button("Clear") {
                    model.clearStack()
                    showQueue = false
                }
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(width: 440)
    }

    /// A pasted row is checked and dimmed; the next one takes the accent wash
    /// and a `next` pill.
    private func queueRow(_ entry: PasteStack.Entry, index: Int) -> some View {
        let pasted = index < stack.cursor
        let isNext = index == stack.cursor
        return HStack(spacing: 8) {
            Group {
                if pasted {
                    Image(systemName: "checkmark")
                } else {
                    Text("\(index + 1)")
                }
            }
            .panelFont(.caption2, digits: true)
            .foregroundStyle(.secondary)
            .frame(width: 16, alignment: .trailing)
            Image(systemName: entry.clip.kind.symbolName)
                .foregroundStyle(.secondary)
            Text(displayText(entry.clip))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(pasted ? .secondary : .primary)
            Spacer(minLength: 0)
            if isNext {
                Text("next")
                    .panelFont(.caption2, .semibold)
                    .foregroundStyle(GanchoTokens.Palette.brandInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(GanchoTokens.Palette.accent, in: .capsule)
            }
            Button {
                model.removeFromStack(entryID: entry.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove from stack")
        }
        .listRowBackground(
            Rectangle().fill(
                isNext ? AnyShapeStyle(GanchoTokens.Palette.accentTint) : AnyShapeStyle(.clear))
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(pasted ? Text("Pasted") : isNext ? Text("Next") : Text(verbatim: ""))
        .accessibilityIdentifier("paste-stack-row")
    }

    /// Kinds only for secrets, in Private Mode and during an unrevealed share.
    private func displayText(_ item: ClipItem) -> String {
        guard !model.previewsHidden, !ClipSafePresentation.requiresMasking(item) else {
            return ClipSafePresentation.masked
        }
        return item.title.isEmpty ? item.preview : item.title
    }
}
