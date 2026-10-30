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
    @State private var approvedRecognizedText: Set<UUID> = []
    @State private var sharedImages: [UUID: ReviewedImageDerivative] = [:]
    @State private var preparingImages: Set<UUID> = []
    @State private var imageFailed = false
    @State private var loading = true
    @State private var failed = false
    @State private var changed = false
    @State private var clientName = ""
    @State private var grant: MCPClientGrant?
    @State private var operation: Task<Void, Never>?
    @State private var generation = UUID()

    @State private var prepared: PreparedSelectedContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Prepare context for AI…").panelFont(.headline)
            Text(
                "Up to 100 text clips and 64 KiB including headers. Nothing is saved or sent automatically."
            )
            .panelFont(.caption)
            if loading { ProgressView() }
            TextSelectionReviewList(
                parts: $parts, disabled: operation != nil || grant != nil,
                imageChoices: ImageReviewChoices(
                    approvedText: $approvedRecognizedText,
                    sharedImages: Set(sharedImages.keys), preparingImages: preparingImages,
                    shareImage: shareImage))
            ScrollView {
                Text(verbatim: prepared?.markdown ?? "")
                    .panelFont(.body)
                    .textSelection(.disabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // The exact outbound pixels, scaled only for display.
                ForEach(parts.filter { sharedImages[$0.id] != nil }) { part in
                    if let image = sharedImages[part.id], let pixels = NSImage(data: image.data) {
                        Image(nsImage: pixels).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 220, alignment: .leading)
                            .accessibilityLabel(
                                Text("Reviewed image, \(image.width) × \(image.height) pixels")
                            )
                            .accessibilityIdentifier("ai-context-shared-image")
                    }
                }
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
            if imageFailed {
                Text("Couldn’t prepare this image. Remove it or share its text instead.")
                    .foregroundStyle(.red)
            }
            if prepared?.isCopyable == false {
                Text("Images are shared only through MCP access, not copied.")
                    .panelFont(.caption).foregroundStyle(.secondary)
            }
            if prepared == nil && !loading {
                Text("Remove incompatible clips or reduce the context below 64 KiB.")
                    .foregroundStyle(.red)
            }
            if changed {
                Text("The selection or clipboard changed. Review and try again.").foregroundStyle(
                    .orange)
            }
            if let grant {
                Text("Read-only access expires in one hour. Revoke it in MCP Access.").panelFont(
                    .caption)
                Text(verbatim: connectionCommand(for: grant.id))
                    .font(.caption.monospaced()).textSelection(.disabled)
                    .accessibilityIdentifier("ai-context-connection-command")
                Button("Copy connection command") { copyConnectionCommand() }
                    .disabled(operation != nil)
                    .accessibilityIdentifier("ai-context-copy-command-button")
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
                    .ganchoButtonStyle(.primary)
                    .disabled(loading || prepared?.isCopyable != true || operation != nil)
                    .accessibilityIdentifier("ai-context-copy-button")
            }
        }
        .padding(20).frame(width: 580, height: 570)
        .task { await load() }
        .onChange(of: parts, initial: true) { prepare() }
        .onChange(of: approvedRecognizedText) { prepare() }
        .onChange(of: sharedImages) { prepare() }
        .onChange(of: model.previewsHidden) { _, hidden in
            if hidden { cancel() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)
        ) { _ in
            if !model.panel.isVisible { cancel() }
        }
        .onDisappear { invalidate() }
    }

    private func prepare() {
        prepared = try? SelectedContextFormatter.format(
            parts, approvedRecognizedText: approvedRecognizedText, reviewedImages: sharedImages)
    }

    private func shareImage(_ id: UUID) {
        guard let store = model.textReuseReader, operation == nil else { return }
        let request = generation
        imageFailed = false
        preparingImages.insert(id)
        Task {
            defer { if generation == request { preparingImages.remove(id) } }
            do {
                let derivative = try await ReviewedImagePreparation.derivative(
                    for: id, from: store)
                guard !Task.isCancelled, generation == request, !model.previewsHidden,
                    parts.contains(where: { $0.id == id })
                else { return }
                sharedImages[id] = derivative
            } catch {
                if generation == request { imageFailed = true }
            }
        }
    }

    private func load() async {
        let request = generation
        defer { loading = false }
        guard !model.previewsHidden, let store = model.textReuseReader else {
            failed = true
            return
        }
        do {
            let loaded = try await CombinedTextService().load(
                ids: ids, from: store, recognizedText: model.storedImageTextReader)
            guard !Task.isCancelled, generation == request, !model.previewsHidden
            else { return }
            parts = loaded
        } catch { if !Task.isCancelled, generation == request { failed = true } }
    }

    private func deliver(asGrant: Bool) {
        guard let store = model.textReuseReader, operation == nil else { return }
        failed = false
        changed = false
        let expected = parts
        let approved = approvedRecognizedText
        let images = sharedImages
        let name = clientName
        let revision = NSPasteboard.general.changeCount
        let request = generation
        operation = Task {
            defer { if generation == request { operation = nil } }
            do {
                let outcome = try await SelectedContextDelivery.perform(
                    expected: expected, approvedRecognizedText: approved,
                    reviewedImages: images, from: store,
                    recognizedText: model.storedImageTextReader,
                    isAllowed: {
                        generation == request && !model.preferences.isPrivateModePaused
                            && model.pendingDeletionIDs.isDisjoint(with: expected.map(\.id))
                    },
                    // Only a copy writes the clipboard; a grant never depends on it.
                    destinationUnchanged: {
                        asGrant || revision == NSPasteboard.general.changeCount
                    },
                    deliver: { prepared in
                        if asGrant {
                            grant = try model.createSelectedContextGrant(prepared, clientName: name)
                        } else {
                            guard prepared.isCopyable else {
                                throw SelectedContextError.incompatibleSelection
                            }
                            writePlainText(prepared.markdown)
                        }
                    })
                guard !Task.isCancelled, generation == request else { return }
                switch outcome {
                case .delivered: if !asGrant { dismiss() }
                case .changed(let current):
                    approvedRecognizedText = SelectedContextDelivery.retainedApprovals(
                        approved, reviewed: expected, current: current)
                    sharedImages = SelectedContextDelivery.retainedImages(
                        images, reviewed: expected, current: current)
                    parts = current
                    changed = true
                case .blocked: failed = true
                }
            } catch is CancellationError { return } catch {
                if !Task.isCancelled, generation == request { failed = true }
            }
        }
    }

    private func copyConnectionCommand() {
        guard operation == nil, !model.preferences.isPrivateModePaused,
            let grant,
            model.mcpConfig.grants.first(where: { $0.id == grant.id })?.state() == .active
        else { return }
        writePlainText(connectionCommand(for: grant.id))
    }

    private func connectionCommand(for id: UUID) -> String {
        "gancho mcp --grant \(id.uuidString)"
    }

    private func writePlainText(_ text: String) {
        #if DEBUG
            guard !CommandLine.arguments.contains("-ui-test-paste-sink") else { return }
        #endif
        SystemPasteboardWriter().write(.text(text), asPlainText: true)
    }

    private func invalidate() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        parts = []
        approvedRecognizedText = []
        sharedImages = [:]
        preparingImages = []
        imageFailed = false
        grant = nil
        clientName = ""
    }

    private func cancel() {
        invalidate()
        dismiss()
    }
}
