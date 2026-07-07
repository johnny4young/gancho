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
    @State private var showQueue = false

    var body: some View {
        if !model.pasteStackEntries.isEmpty {
            Button {
                showQueue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                    Text("\(model.pasteStackEntries.count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                    ForEach(model.pasteStackEntries.prefix(3)) { entry in
                        Image(systemName: entry.clip.kind.symbolName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    if model.pasteStackEntries.count > 3 {
                        Text("+\(model.pasteStackEntries.count - 3)")
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
            .accessibilityLabel("Paste stack, \(model.pasteStackEntries.count) items")
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
                ForEach(Array(model.pasteStackEntries.enumerated()), id: \.element.id) {
                    index, entry in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Image(systemName: entry.clip.kind.symbolName)
                            .foregroundStyle(.secondary)
                        Text(displayText(entry.clip))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Button {
                            model.removeFromStack(entryID: entry.id)
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
                    if model.pasteStackEntries.isEmpty { showQueue = false }
                }
                .disabled(model.pasteStackEntries.isEmpty)
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
