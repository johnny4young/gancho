import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

/// The paste queue made visible. `AppModel.pasteStack` already worked, but it
/// only lived behind a context menu — a hidden power feature. This footer strip
/// surfaces it: a compact row when the queue is non-empty, a popover to
/// reorder / remove / paste. The queue is session-local and never syncs.
struct PasteStackStrip: View {
    @Environment(AppModel.self) private var model
    @State private var showQueue = false

    var body: some View {
        if !model.pasteStack.isEmpty {
            Button {
                showQueue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                    Text("\(model.pasteStack.count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                    ForEach(model.pasteStack.prefix(3)) { item in
                        Image(systemName: item.kind.symbolName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if model.pasteStack.count > 3 {
                        Text("+\(model.pasteStack.count - 3)")
                            .font(.caption2)
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
            .accessibilityLabel("Paste stack, \(model.pasteStack.count) items")
            .popover(isPresented: $showQueue, arrowEdge: .top) {
                queuePopover
            }
        }
    }

    private var queuePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Paste stack").font(.headline)
                Spacer()
                if let shortcut = KeyboardShortcuts.getShortcut(for: .pasteFromStack) {
                    Text(verbatim: "\(shortcut)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Text("Pastes front to back — one per keypress.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(Array(model.pasteStack.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Image(systemName: item.kind.symbolName)
                            .foregroundStyle(.secondary)
                        Text(displayText(item))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            model.removeFromStack(id: item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove from stack")
                    }
                }
                .onMove { source, destination in
                    model.moveInStack(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .frame(width: 300, height: 200)

            HStack {
                Button("Paste next") {
                    model.pasteNextFromStack()
                    if model.pasteStack.isEmpty { showQueue = false }
                }
                .disabled(model.pasteStack.isEmpty)
                Spacer()
                Button("Clear") {
                    model.clearStack()
                    showQueue = false
                }
                .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private func displayText(_ item: ClipItem) -> String {
        item.title.isEmpty ? item.preview : item.title
    }
}
