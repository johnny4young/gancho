import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// Menu-bar shell (pre-alpha). The real panel (a Liquid Glass NSPanel with a
/// global hotkey) replaces this once the privacy and capture spikes land; this
/// shell exists so the target builds, runs, and proves the capture wiring end
/// to end.
@main
struct GanchoMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Gancho", systemImage: "paperclip") {
            ContentView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

@Observable
@MainActor
final class AppModel {
    var captures: [ClipItem] = []

    private let monitor = MacPasteboardMonitor()
    private let classifier = RuleClassifier()
    private let store = InMemoryClipboardStore()

    init() {
        monitor.onCapture = { [weak self] capture in
            guard let self else { return }
            let item = Self.makeItem(from: capture, classifier: classifier)
            Task {
                try? await self.store.insert(item)
                self.captures = (try? await self.store.items()) ?? []
            }
        }
        monitor.start()
    }

    /// Maps a capture payload to a clip. Text-like payloads go through the
    /// tier-0 classifier; images and file references map directly — their
    /// kind is structural, not content-derived.
    private static func makeItem(
        from capture: PasteboardCapture, classifier: RuleClassifier
    ) -> ClipItem {
        let kind: ClipContentKind
        let preview: String
        let contentHash: String

        switch capture.payload {
        case .image(let data, let typeIdentifier):
            kind = .image
            preview = "Image (\(typeIdentifier), \(data.count) bytes)"
            contentHash = ClipItem.hash(of: data, kind: kind)
        case .fileReferences(let urls):
            kind = .fileReference
            preview = urls.map(\.lastPathComponent).joined(separator: ", ")
            contentHash = ClipItem.hash(
                of: urls.map(\.absoluteString).joined(separator: "\n"), kind: kind)
        default:
            let raw = capture.textRepresentation ?? ""
            kind = classifier.classify(raw)
            // Canonicalize BEFORE hashing so tracking params and rich-payload
            // noise never defeat dedupe.
            let text = ContentNormalizer.canonicalText(raw, kind: kind)
            preview = String(text.prefix(120))
            contentHash = ClipItem.hash(of: text, kind: kind)
            let item = ClipItem(
                kind: kind,
                preview: preview,
                contentHash: contentHash,
                sourceAppBundleID: capture.sourceAppBundleID
            )
            // Accidental secrets get masked + short-lived at ingestion.
            return SensitiveIngestionPolicy.decorate(
                item, finding: SensitiveDataDetector().detect(text), originalText: text)
        }

        return ClipItem(
            kind: kind,
            preview: preview,
            contentHash: contentHash,
            sourceAppBundleID: capture.sourceAppBundleID
        )
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            Text("Gancho — pre-alpha")
                .font(.headline)
                .padding(.bottom, GanchoTokens.Spacing.xxs)

            if model.captures.isEmpty {
                Text("Copy something — it will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.captures.prefix(5)) { item in
                    HStack(spacing: GanchoTokens.Spacing.xs) {
                        Text(item.kind.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.preview)
                            .lineLimit(1)
                    }
                }
            }

            Divider()
            Button("Quit Gancho") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 320)
    }
}
