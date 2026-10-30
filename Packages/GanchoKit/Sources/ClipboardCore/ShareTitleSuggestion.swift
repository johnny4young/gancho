import Foundation

/// The title the share sheet starts with: the one the sharing app gave the
/// item (a page title), never the shared text itself, which may be a secret.
public enum ShareTitleSuggestion {
    public static func title(
        attributedTitle: String?, contentText: String?, sharedTexts: [String]
    ) -> String? {
        let shared = sharedTexts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for candidate in [attributedTitle, contentText] {
            guard let title = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                !title.isEmpty, !title.contains(where: \.isNewline),
                URL(string: title)?.scheme == nil,
                !shared.contains(where: { $0.contains(title) || title.contains($0) && !$0.isEmpty })
            else { continue }
            return String(title.prefix(200))
        }
        return nil
    }
}
