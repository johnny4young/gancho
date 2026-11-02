import GanchoDesign
import GanchoKit
import SwiftUI

/// The snippet placeholders, one click from the caret. A modifier applies to
/// the placeholder the caret is in or right after.
struct InsertPlaceholderChips: View {
    let editor: SnippetBodyEditorHandle

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            Text("Insert placeholder").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                chip("{field}", .field(name: "field", defaultValue: nil), id: "field") {
                    editor.insert("{field}", selecting: NSRange(location: 1, length: 5))
                }
                insertion("{clipboard}", .clipboard(offset: 0), id: "clipboard")
                insertion("{clipboard offset=1}", .clipboard(offset: 1), id: "clipboard-offset")
                insertion("{date}", .date(dayOffset: 0), id: "date")
                insertion("{cursor}", .cursor, id: "cursor")
                ForEach(SnippetTemplate.Modifier.allCases, id: \.self) { modifier in
                    chip("| \(modifier.rawValue)", nil, id: modifier.rawValue) {
                        editor.add(modifier)
                    }
                    .disabled(!editor.canAddModifier)
                    .opacity(editor.canAddModifier ? 1 : ButtonStates.disabledOpacity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insert-placeholder-chips")
    }

    private func insertion(
        _ text: String, _ placeholder: SnippetTemplate.Placeholder, id: String
    ) -> some View {
        chip(text, placeholder, id: id) { editor.insert(text) }
    }

    private func chip(
        _ text: String, _ placeholder: SnippetTemplate.Placeholder?, id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: text)
                .font(.caption.monospaced())
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .padding(.vertical, 3)
                .ganchoTintedPill(
                    placeholder.map(GanchoTokens.Syntax.color(for:)) ?? .secondary, wash: 0.15)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("insert-placeholder-\(id)")
    }
}
