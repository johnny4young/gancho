import AppKit
import ClipboardCore
import Combine
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

struct SelectedContextReview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ids: [UUID]
    @State private var parts: [CombinedTextPart] = []
    @State private var loading = true
    @State private var failed = false
    @State private var changed = false
    @State private var clientName = ""
    @State private var grant: MCPClientGrant?
    @State private var operation: Task<Void, Never>?
    @State private var generation = UUID()

    var body: some View {
        let prepared = try? SelectedContextFormatter.format(parts)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Prepare context for AI…").panelFont(.headline)
            Text(
                "Up to 100 text clips and 64 KiB including headers. Nothing is saved or sent automatically."
            )
            .panelFont(.caption)
            if loading { ProgressView() }
            TextSelectionReviewList(parts: $parts, disabled: operation != nil || grant != nil)
            ScrollView {
                Text(verbatim: prepared?.markdown ?? "")
                    .panelFont(.body)
                    .textSelection(.disabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 100)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ai-context-preview")
            if failed {
                Text(
                    "Couldn’t prepare or share this context. Try again; existing access is unchanged."
                )
                .foregroundStyle(.red)
            }
            if prepared == nil && !loading {
                Text("Remove incompatible clips or reduce the context below 64 KiB.")
                    .foregroundStyle(.red)
            }
            if changed {
                Text("The selection or clipboard changed. Review and copy again.").foregroundStyle(
                    .orange)
            }
            if let grant {
                Text("Read-only access expires in one hour. Revoke it in MCP Access.").panelFont(
                    .caption)
                Text(verbatim: "gancho mcp --grant \(grant.id.uuidString)")
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .accessibilityIdentifier("ai-context-connection-command")
            } else {
                TextField("Client name", text: $clientName)
                    .disabled(operation != nil)
                    .accessibilityIdentifier("ai-context-client-field")
                Text(
                    "One-hour, read-only access to these IDs. Enabling MCP reactivates other valid grants."
                )
                .panelFont(.caption).foregroundStyle(.secondary)
                Button("Grant selected context access") { deliver(asGrant: true) }
                    .disabled(
                        loading || prepared == nil
                            || clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || clientName.trimmingCharacters(in: .whitespacesAndNewlines).count
                                > MCPClientGrant.maximumClientNameLength
                            || operation != nil
                    )
                    .accessibilityIdentifier("ai-context-grant-button")
            }
            HStack {
                Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("ai-context-cancel-button")
                Spacer()
                Button("Copy Markdown") { deliver(asGrant: false) }.keyboardShortcut(.defaultAction)
                    .disabled(loading || prepared == nil || operation != nil)
                    .accessibilityIdentifier("ai-context-copy-button")
            }
        }
        .padding(20).frame(width: 580, height: 570)
        .task { await load() }
        .onChange(of: model.preferences.isPrivateModePaused) { _, paused in
            if paused { cancel() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)
        ) { _ in
            if !model.panel.isVisible { cancel() }
        }
        .onDisappear { invalidate() }
    }

    private func load() async {
        let request = generation
        defer { loading = false }
        guard !model.preferences.isPrivateModePaused, let store = model.fullStore else {
            failed = true
            return
        }
        do {
            let loaded = try await CombinedTextService().load(ids: ids, from: store)
            guard !Task.isCancelled, generation == request, !model.preferences.isPrivateModePaused
            else { return }
            parts = loaded
        } catch { if !Task.isCancelled, generation == request { failed = true } }
    }

    private func deliver(asGrant: Bool) {
        guard let store = model.fullStore, operation == nil else { return }
        failed = false
        changed = false
        let expected = parts
        let name = clientName
        let revision = NSPasteboard.general.changeCount
        let request = generation
        operation = Task {
            defer { if generation == request { operation = nil } }
            do {
                let outcome = try await SelectedContextDelivery.perform(
                    expected: expected, from: store,
                    isAllowed: {
                        generation == request && !model.preferences.isPrivateModePaused
                            && model.pendingDeletionIDs.isDisjoint(with: expected.map(\.id))
                    },
                    destinationUnchanged: {
                        asGrant || revision == NSPasteboard.general.changeCount
                    },
                    deliver: { prepared in
                        if asGrant {
                            grant = try model.createSelectedContextGrant(prepared, clientName: name)
                        } else {
                            #if DEBUG
                                if !CommandLine.arguments.contains("-ui-test-paste-sink") {
                                    SystemPasteboardWriter().write(
                                        .text(prepared.markdown), asPlainText: true)
                                }
                            #else
                                SystemPasteboardWriter().write(
                                    .text(prepared.markdown), asPlainText: true)
                            #endif
                        }
                    })
                guard !Task.isCancelled, generation == request else { return }
                switch outcome {
                case .delivered: if !asGrant { dismiss() }
                case .changed(let current):
                    parts = current
                    changed = true
                case .blocked: failed = true
                }
            } catch is CancellationError { return } catch {
                if !Task.isCancelled, generation == request { failed = true }
            }
        }
    }

    private func invalidate() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        parts = []
        grant = nil
        clientName = ""
    }

    private func cancel() {
        invalidate()
        dismiss()
    }
}
