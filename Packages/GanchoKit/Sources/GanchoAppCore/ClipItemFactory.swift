import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit

/// Turns a captured pasteboard event into a classified, normalized,
/// sensitivity-decorated `ClipItem` plus the full `ClipContent` the store
/// persists — the single home for the capture→ClipItem mapping the macOS shell
/// used to inline in `AppModel`.
///
/// Pure and dependency-injected: the classifier, secret detector, sensitive
/// lifetime, and the intelligence `detectSecrets` toggle are all passed in, so
/// there is no `self` and no platform surface. Every payload case (image, file
/// references, rich text, and the plain-text default) maps exactly as the
/// inlined code did — same preview strings, the same `ClipItem.hash(...)`
/// inputs, the same content mapping, and the same sensitive branch that stores
/// masked `.text` for a flagged rich clip instead of the `.rtf` binary.
public enum ClipItemFactory {
    /// Capture payload → classified, normalized, sensitivity-decorated clip
    /// plus its full content for the store.
    public static func make(
        from capture: PasteboardCapture,
        classifier: RuleClassifier,
        detector: SensitiveDataDetector,
        sensitiveLifetime: TimeInterval,
        detectSecrets: Bool = true
    ) -> (ClipItem, ClipContent?) {
        switch capture.payload {
        case .image(let data, let typeIdentifier):
            let item = ClipItem(
                kind: .image,
                preview: "Image (\(ByteSize.formatted(data.count)))",
                contentHash: ClipItem.hash(of: data, kind: .image),
                sourceAppBundleID: capture.sourceAppBundleID)
            return (item, .binary(data: data, typeIdentifier: typeIdentifier))
        case .fileReferences(let urls):
            let paths = urls.map(\.path)
            let item = ClipItem(
                kind: .fileReference,
                preview: urls.map(\.lastPathComponent).joined(separator: ", "),
                contentHash: ClipItem.hash(of: paths.joined(separator: "\n"), kind: .fileReference),
                sourceAppBundleID: capture.sourceAppBundleID)
            return (item, .fileReferences(paths))
        case .richText(let rtf, let plain):
            let text = plain ?? ""
            let item = decoratedTextItem(
                text: text, capture: capture, classifier: classifier, detector: detector,
                sensitiveLifetime: sensitiveLifetime, detectSecrets: detectSecrets)
            return (
                item,
                item.isSensitive ? .text(text) : .binary(data: rtf, typeIdentifier: "public.rtf")
            )
        default:
            let text = capture.textRepresentation ?? ""
            let item = decoratedTextItem(
                text: text, capture: capture, classifier: classifier, detector: detector,
                sensitiveLifetime: sensitiveLifetime, detectSecrets: detectSecrets)
            return (item, .text(ContentNormalizer.canonicalText(text, kind: item.kind)))
        }
    }

    private static func decoratedTextItem(
        text: String, capture: PasteboardCapture, classifier: RuleClassifier,
        detector: SensitiveDataDetector, sensitiveLifetime: TimeInterval,
        detectSecrets: Bool = true
    ) -> ClipItem {
        let kind = classifier.classify(text)
        let canonical = ContentNormalizer.canonicalText(text, kind: kind)
        let item = ClipItem(
            kind: kind,
            preview: String(canonical.prefix(120)),
            contentHash: ClipItem.hash(of: canonical, kind: kind),
            sourceAppBundleID: capture.sourceAppBundleID)
        // Intelligence toggle off ⇒ skip secret detection/masking. The
        // password-manager veto (ConcealedType, pre-read) is separate and stays.
        guard detectSecrets else { return item }
        return SensitiveIngestionPolicy.decorate(
            item, finding: detector.detect(canonical), originalText: canonical,
            sensitiveLifetime: sensitiveLifetime)
    }
}
