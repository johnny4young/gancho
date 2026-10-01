import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit

public enum SnippetDraftRecovery {
    /// Explicit recovery uses the same classification and privacy policy as capture.
    public static func prepare(
        _ fields: SnippetDraft.Fields, sensitiveLifetime: TimeInterval,
        detectSecrets: Bool, fallbackTitle: String
    ) throws -> (item: ClipItem, text: String) {
        let (original, content) = ClipItemFactory.make(
            from: PasteboardCapture(text: fields.body), classifier: RuleClassifier(),
            detector: SensitiveDataDetector(), sensitiveLifetime: sensitiveLifetime,
            detectSecrets: detectSecrets, sourceDeviceName: nil)
        var item = original
        guard !ClipSafePresentation.requiresMasking(item), case .text(let text) = content else {
            throw SnippetDraftSaveError.protectedContent
        }
        item.title =
            fields.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackTitle : fields.title
        return (item, text)
    }
}
