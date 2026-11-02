import Foundation
import GanchoKit

/// Suggested snippets: clips used often enough to offer keeping. The Library
/// lists them and the use-time toast shares the same answers.
extension AppModel {
    func snippetSuggestions() async -> SnippetSuggestions {
        (try? await grdbForEngines?.snippetSuggestions()) ?? .empty
    }

    /// True once the answer is saved; a failure says so and keeps the card.
    func decideSnippetSuggestion(
        _ item: ClipItem, _ decision: SnippetSuggestionDecision
    ) async -> Bool {
        guard let grdbForEngines else { return false }
        do {
            try await grdbForEngines.decideSnippetSuggestion(id: item.id, decision)
            return true
        } catch {
            toasts.show(GanchoToast(message: "Couldn’t update the suggestion.", style: .warning))
            return false
        }
    }
}
