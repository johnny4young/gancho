import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// iOS companion shell (pre-alpha). Proves the honest capture story end to
/// end: intent-based reads only (capture button, UIPasteControl, share
/// extension inbox), detect-before-read hints, and NO background polling —
/// the App Review notes promise exactly this behavior.
@main
struct GanchoiOSApp: App {
    @State private var model = IOSAppModel()

    var body: some Scene {
        WindowGroup {
            CaptureView()
                .environment(model)
        }
    }
}

@Observable
@MainActor
final class IOSAppModel {
    var captures: [ClipItem] = []
    var hints = IntentionalPasteboardSource.ContentHints()

    private let source = IntentionalPasteboardSource()
    private let classifier = RuleClassifier()
    private let store = InMemoryClipboardStore()

    /// Metadata-only refresh — safe on every activation, never alerts.
    func refreshHints() async {
        hints = await source.hints()
    }

    /// The user-initiated read (system paste transparency applies).
    func saveClipboard() async {
        guard let capture = source.captureNow() else { return }
        await ingest(capture)
    }

    /// Captures handed over by the share extension through the App Group.
    func drainSharedInbox() async {
        guard let inbox = SharedInbox.inAppGroup() else { return }
        for capture in (try? inbox.drain()) ?? [] {
            await ingest(capture)
        }
    }

    /// UIPasteControl handoff: the system mediates the tap, so this path
    /// never shows an alert. Providers carry text, URLs, or images.
    func ingest(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: UIImage.self) {
                _ = provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let png = (object as? UIImage)?.pngData() else { return }
                    Task { @MainActor in
                        await self?.ingest(
                            PasteboardCapture(
                                payload: .image(data: png, typeIdentifier: "public.png")))
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                    guard let text = object as? String, !text.isEmpty else { return }
                    Task { @MainActor in
                        await self?.ingest(PasteboardCapture(text: text))
                    }
                }
            }
        }
    }

    private func ingest(_ capture: PasteboardCapture) async {
        let item = makeItem(from: capture)
        try? await store.insert(item)
        captures = (try? await store.items()) ?? []
    }

    private func makeItem(from capture: PasteboardCapture) -> ClipItem {
        switch capture.payload {
        case .image(let data, let typeIdentifier):
            return ClipItem(
                kind: .image,
                preview: "Image (\(typeIdentifier), \(data.count) bytes)",
                contentHash: ClipItem.hash(of: data, kind: .image),
                sourceAppBundleID: capture.sourceAppBundleID)
        default:
            let raw = capture.textRepresentation ?? ""
            let kind = classifier.classify(raw)
            let text = ContentNormalizer.canonicalText(raw, kind: kind)
            return ClipItem(
                kind: kind,
                preview: String(text.prefix(120)),
                contentHash: ClipItem.hash(of: text, kind: kind),
                sourceAppBundleID: capture.sourceAppBundleID)
        }
    }
}

struct CaptureView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("Pasteboard") {
                    hintsRow
                    Button("Save clipboard", systemImage: "square.and.arrow.down") {
                        Task { await model.saveClipboard() }
                    }
                    .accessibilityIdentifier("capture-button")
                    PasteControlView { providers in
                        model.ingest(providers: providers)
                    }
                    .frame(height: 36)
                    .accessibilityIdentifier("paste-control")
                }

                Section("Captured") {
                    if model.captures.isEmpty {
                        Text("Nothing captured yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.captures) { item in
                            HStack(spacing: GanchoTokens.Spacing.xs) {
                                Text(item.kind.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(item.preview)
                                    .lineLimit(1)
                            }
                            .accessibilityIdentifier("clip-row")
                        }
                    }
                }

                Section {
                    Text("Gancho never reads your pasteboard in the background.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Gancho")
            .accessibilityIdentifier("capture-screen")
        }
        .task { await activate() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await activate() }
        }
    }

    /// Foreground activation: metadata hints + extension inbox, no reads.
    private func activate() async {
        await model.refreshHints()
        await model.drainSharedInbox()
    }

    @ViewBuilder
    private var hintsRow: some View {
        if model.hints.hasContent {
            Label(hintText, systemImage: "doc.on.clipboard")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pasteboard-hints")
        } else {
            Label("Pasteboard is empty", systemImage: "doc.on.clipboard")
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("pasteboard-hints")
        }
    }

    private var hintText: String {
        var parts: [String] = []
        if model.hints.probableWebURL { parts.append("link") }
        if model.hints.probableWebSearch { parts.append("search text") }
        if model.hints.number { parts.append("number") }
        let detail = parts.isEmpty ? "content" : parts.joined(separator: ", ")
        return "Has \(detail) — not read yet"
    }
}

/// `UIPasteControl` wrapper: the system button that pastes WITHOUT any
/// banner or alert, because the OS itself mediates the user's tap.
struct PasteControlView: UIViewRepresentable {
    let onPaste: ([NSItemProvider]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaste: onPaste)
    }

    func makeUIView(context: Context) -> UIPasteControl {
        let control = UIPasteControl()
        control.target = context.coordinator.target
        return control
    }

    func updateUIView(_ control: UIPasteControl, context: Context) {}

    @MainActor
    final class Coordinator {
        let target: PasteTarget

        init(onPaste: @escaping ([NSItemProvider]) -> Void) {
            target = PasteTarget(onPaste: onPaste)
        }
    }

    /// Hidden responder the control targets; accepts text, URLs, images.
    @MainActor
    final class PasteTarget: UIResponder {
        private let onPaste: ([NSItemProvider]) -> Void

        init(onPaste: @escaping ([NSItemProvider]) -> Void) {
            self.onPaste = onPaste
            super.init()
            pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
                UTType.plainText.identifier,
                UTType.url.identifier,
                UTType.image.identifier,
            ])
        }

        override func paste(itemProviders: [NSItemProvider]) {
            onPaste(itemProviders)
        }
    }
}
