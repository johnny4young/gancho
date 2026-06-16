import ClipboardCore
import GanchoAI
import GanchoKit
import UIKit

/// The one place "save the current pasteboard into Gancho" lives, shared by
/// the Save Clipboard intent/control and the keyboard's reverse-capture
/// button. Returns a content-free `Outcome` so each surface localizes its own
/// confirmation (the helper never builds user-facing prose).
enum SharedCapture {
    enum Outcome: Sendable {
        case savedText
        case savedImage
        case empty
        case storeUnavailable
    }

    /// Reads `UIPasteboard.general`, classifies + normalizes, applies the
    /// sensitive-data policy, and inserts. Same pipeline the app's capture
    /// uses — no logic fork.
    @MainActor
    static func saveCurrentClipboard() async -> Outcome {
        guard let store = try? IntentStore.open() else { return .storeUnavailable }
        let pasteboard = UIPasteboard.general

        if let image = pasteboard.image, let png = image.pngData() {
            let item = ClipItem(
                kind: .image, preview: "Image (\(ByteSize.formatted(png.count)))",
                contentHash: ClipItem.hash(of: png, kind: .image))
            _ = try? await store.insert(
                item, content: .binary(data: png, typeIdentifier: "public.png"))
            return .savedImage
        }
        guard let text = pasteboard.string, !text.isEmpty else { return .empty }

        let classifier = RuleClassifier()
        let kind = classifier.classify(text)
        let canonical = ContentNormalizer.canonicalText(text, kind: kind)
        let item = SensitiveIngestionPolicy.decorate(
            ClipItem(
                kind: kind, preview: String(canonical.prefix(120)),
                contentHash: ClipItem.hash(of: canonical, kind: kind)),
            finding: SensitiveDataDetector().detect(canonical), originalText: canonical)
        _ = try? await store.insert(item, content: .text(canonical))
        return .savedText
    }
}
