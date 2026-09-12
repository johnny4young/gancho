import AppKit
import GanchoAppCore
import GanchoDesign
import SwiftUI

struct ManualOCRReview: View {
    @Environment(AppModel.self) private var model
    @State private var draft: String
    @State private var isWorking = false
    @State private var failed = false
    @State private var clipboardChanged = false
    @State private var actionTask: Task<Void, Never>?

    init(text: String) { _draft = State(initialValue: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review recognized text").font(.headline)
            Text("Changes stay here until you copy or save them.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.body).accessibilityIdentifier("ocr-review-text")
                .disabled(isWorking)
            if clipboardChanged {
                Text("Text ready — clipboard unchanged").foregroundStyle(.secondary)
            }
            if failed {
                Text("This action couldn’t be completed. Check the source and try again.")
                    .foregroundStyle(.red).accessibilityIdentifier("ocr-review-error")
            }
            HStack {
                Button("Close") { model.manualOCRWindow.close() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("ocr-review-close")
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("Save as clip") { run(save: true) }
                    .accessibilityIdentifier("ocr-review-save")
                Button("Copy text") { run(save: false) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("ocr-review-copy")
            }
            .disabled(isWorking)
        }
        .padding(20).frame(minWidth: 420, minHeight: 280)
        .onChange(of: model.preferences.isPrivateModePaused) { _, paused in
            if paused { model.manualOCRWindow.close() }
        }
        .onDisappear {
            actionTask?.cancel()
            actionTask = nil
            draft = ""
        }
    }

    private func run(save: Bool) {
        isWorking = true
        failed = false
        clipboardChanged = false
        actionTask = Task {
            defer {
                isWorking = false
                actionTask = nil
            }
            if save {
                let validated = await model.manualOCR.reviewedText(draft)
                guard !Task.isCancelled else { return }
                guard let text = validated else {
                    rejectSource()
                    return
                }
                guard await model.saveManualText(text) else {
                    failed = true
                    return
                }
            } else {
                let result = await model.manualOCR.copyReviewedText(
                    draft, clipboardRevision: { NSPasteboard.general.changeCount },
                    copy: { model.writeManualText($0) })
                guard !Task.isCancelled else { return }
                switch result {
                case .copied: break
                case .clipboardChanged:
                    clipboardChanged = true
                    return
                case .unavailable:
                    rejectSource()
                    return
                }
            }
            guard !Task.isCancelled else { return }
            model.manualOCRWindow.close()
        }
    }

    private func rejectSource() {
        draft = ""
        model.manualOCR.cancel()
        failed = true
    }
}

@MainActor final class ManualOCRWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var model: AppModel?
    private var restorePanel = false
    var isVisible: Bool { window?.isVisible == true }

    func show(model: AppModel) {
        guard !model.manualOCR.text.isEmpty else { return }
        self.model = model
        restorePanel = model.panel.isVisible
        model.panel.hide()
        let hosting = NSHostingController(
            rootView: ManualOCRReview(text: model.manualOCR.text).environment(model).ganchoTinted())
        let created = NSWindow(contentViewController: hosting)
        created.title = String(localized: "Review recognized text")
        created.styleMask = [.titled, .closable, .resizable]
        created.isReleasedWhenClosed = false
        created.setContentSize(NSSize(width: 560, height: 400))
        created.contentMinSize = NSSize(width: 420, height: 280)
        created.center()
        created.delegate = self
        window = created
        created.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        model?.manualOCR.cancel()
        if restorePanel, let model { model.panel.show(model: model) }
        restorePanel = false
        window?.contentViewController = nil
        window = nil
        model = nil
    }
}
