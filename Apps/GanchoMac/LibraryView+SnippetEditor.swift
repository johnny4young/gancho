import AppKit
import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

// The snippet editor pane — split from `LibraryView` so the file stays
// within the length budget; it reads the view's editor state directly.
extension LibraryView {
    // MARK: - Snippet editor

    func snippetEditor(_ snippet: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            TextField("Snippet title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .focused($focusedField, equals: .title)
                .onSubmit { save() }
                .accessibilityIdentifier("snippet-title")

            HStack(spacing: GanchoTokens.Spacing.xs) {
                kindPill(snippet.kind)
                keywordField
                Spacer(minLength: 0)
            }

            SyntaxTextView(text: $snippetBody)
                .frame(minHeight: 220)
                .clipShape(roundedCard)
                .overlay(
                    roundedCard.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))

            Text(
                // swiftlint:disable:next line_length
                "Type the keyword in the panel to insert this snippet. Add {field} placeholders to fill in before pasting."
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)

            let fields = SnippetTemplate.fields(in: snippetBody)
            if !fields.isEmpty {
                fieldStrip(fields)
            }

            snippetFooter(for: snippet)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: focusedField) { previous, _ in
            // Commit a rename or keyword edit the moment focus leaves the field —
            // no need to hunt for Save for those quick edits.
            if previous == .title || previous == .keyword { save() }
        }
    }

    func kindPill(_ kind: ClipContentKind) -> some View {
        Label(LocalizedStringKey(kind.rawValue), systemImage: kind.symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, GanchoTokens.Spacing.xxs)
            .background(.quaternary, in: Capsule())
            .accessibilityIdentifier("snippet-kind")
    }

    private var keywordField: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
                .foregroundStyle(GanchoTokens.Palette.accent)
            TextField("Keyword", text: $keyword)
                .textFieldStyle(.plain)
                .font(.callout.monospaced())
                .frame(maxWidth: 160)
                .focused($focusedField, equals: .keyword)
                .onSubmit { save() }
                .accessibilityIdentifier("snippet-keyword")
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, GanchoTokens.Spacing.xxs)
        .background(.quaternary, in: Capsule())
    }

    func fieldStrip(_ fields: [SnippetTemplate.Field]) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            Text("Fields").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                ForEach(fields) { field in
                    Text(verbatim: "{\(field.name)}")
                        .font(.caption.monospaced())
                        .padding(.horizontal, GanchoTokens.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(
                            GanchoTokens.Palette.kindTint(for: .code).opacity(0.15), in: Capsule()
                        )
                        .foregroundStyle(GanchoTokens.Palette.kindTint(for: .code))
                }
            }
        }
    }

    func snippetFooter(for snippet: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            HStack(spacing: GanchoTokens.Spacing.md) {
                Label(
                    "Created \(snippet.createdAt.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "clock"
                )
                Label("\(snippetBody.count) characters", systemImage: "text.alignleft")
                if snippet.uses > 0 {
                    Label("\(snippet.uses) uses", systemImage: "arrow.up.right")
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: GanchoTokens.Spacing.xs) {
                ActionButton(
                    "Move to history", systemImage: "arrow.uturn.backward",
                    identifier: "snippet-demote"
                ) {
                    demote()
                }
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ActionButton("Copy", systemImage: "doc.on.doc", identifier: "snippet-copy") {
                    SystemPasteboardWriter().write(.text(snippetBody), asPlainText: true)
                    model.toasts.show(GanchoToast(message: "Copied"))
                }
                ActionButton("Save", systemImage: "checkmark", identifier: "snippet-save") {
                    save()
                }
            }
        }
    }
}
