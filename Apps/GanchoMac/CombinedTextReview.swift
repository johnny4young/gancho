import AppKit
import ClipboardCore
import GanchoAppCore
import GanchoKit
import SwiftUI

/// The sheet identity owns an immutable visible-order selection for one review.
struct CombinedTextSelection: Identifiable {
    let id = UUID()
    let ids: [UUID]
}

struct CombinedTextReview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ids: [UUID]
    @State private var parts: [CombinedTextPart] = []
    @State private var separatorChoice = 1
    @State private var customSeparator = ""
    @State private var loading = true
    @State private var failed = false
    @State private var changed = false
    @State private var copyTask: Task<Void, Never>?
    private let service = CombinedTextService()

    private var separator: String {
        separatorChoice == 0 ? "\n" : separatorChoice == 1 ? "\n\n" : customSeparator
    }
    private var composed: String? { try? service.compose(parts, separator: separator) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Copy combined text").font(.headline)
            Text("Up to 100 clips and 1 MiB. Nothing is saved or pasted automatically.").font(
                .caption)
            if loading { ProgressView() }
            List {
                ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                    HStack {
                        Text("Clip \(index + 1)").monospacedDigit()
                        if case .text(let text) = part.content {
                            Text(verbatim: String(text.prefix(80))).lineLimit(1).foregroundStyle(
                                .secondary)
                        } else {
                            Text(status(part)).lineLimit(1).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Move up", systemImage: "arrow.up") {
                            parts.swapAt(index, index - 1)
                        }
                        .labelStyle(.iconOnly).disabled(index == 0)
                        Button("Move down", systemImage: "arrow.down") {
                            parts.swapAt(index, index + 1)
                        }
                        .labelStyle(.iconOnly).disabled(index + 1 == parts.count)
                        Button("Remove", systemImage: "minus.circle") { parts.remove(at: index) }
                            .labelStyle(.iconOnly)
                    }
                }
            }.frame(height: 140).disabled(copyTask != nil)
            Picker("Separator", selection: $separatorChoice) {
                Text("New line").tag(0)
                Text("Blank line").tag(1)
                Text("Custom").tag(2)
            }.disabled(copyTask != nil)
            if separatorChoice == 2 {
                TextField("Custom separator", text: $customSeparator).disabled(copyTask != nil)
            }
            ScrollView {
                Text(verbatim: composed ?? "").textSelection(.enabled).frame(
                    maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 100).accessibilityIdentifier("combined-text-preview")
            if failed || composed == nil && !loading {
                Text("Remove unavailable or incompatible clips, or reduce the combined size.")
                    .foregroundStyle(.red)
            }
            if changed {
                Text("The selection or clipboard changed. Review and copy again.").foregroundStyle(
                    .orange)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Copy") { copy() }.keyboardShortcut(.defaultAction)
                    .disabled(loading || composed == nil || copyTask != nil)
                    .accessibilityIdentifier("combined-text-copy")
            }
        }.padding(20).frame(width: 540, height: 470)
            .task { await load() }
            .onChange(of: model.preferences.isPrivateModePaused) { _, paused in
                if paused { dismiss() }
            }
            .onDisappear {
                copyTask?.cancel()
                copyTask = nil
                parts = []
            }
    }

    private func status(_ part: CombinedTextPart) -> LocalizedStringKey {
        switch part.content {
        case .text: "Text ready"
        case .incompatible: "Not a text clip"
        case .protected: "Protected clip"
        case .unavailable: "Clip unavailable"
        case .tooLarge: "Text exceeds the size limit"
        }
    }

    private func load() async {
        defer { loading = false }
        guard !model.preferences.isPrivateModePaused, let store = model.fullStore else {
            failed = true
            return
        }
        do {
            let loaded = try await service.load(ids: ids, from: store)
            guard !Task.isCancelled, !model.preferences.isPrivateModePaused else { return }
            parts = loaded
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func copy() {
        guard let store = model.fullStore else { return }
        let expected = parts
        let separator = separator
        let revision = NSPasteboard.general.changeCount
        copyTask = Task {
            defer { copyTask = nil }
            do {
                let outcome = try await CombinedTextCopy.perform(
                    expected: expected, separator: separator, from: store,
                    clipboardUnchanged: { revision == NSPasteboard.general.changeCount },
                    isAllowed: {
                        !model.preferences.isPrivateModePaused
                            && !expected.contains(where: {
                                model.pendingDeletionIDs.contains($0.id)
                            })
                    },
                    write: { result in
                        #if DEBUG
                            if !CommandLine.arguments.contains("-ui-test-paste-sink") {
                                SystemPasteboardWriter().write(.text(result), asPlainText: true)
                            }
                        #else
                            SystemPasteboardWriter().write(.text(result), asPlainText: true)
                        #endif
                    })
                switch outcome {
                case .copied: dismiss()
                case .changed(let current):
                    parts = current
                    changed = true
                case .blocked, .invalid: failed = true
                }
            } catch is CancellationError {
                return
            } catch { failed = true }
        }
    }
}
