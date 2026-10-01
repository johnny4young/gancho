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
            if draft.requiresRecovery {
                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                    Label(
                        "The original snippet was removed. Your draft is still here.",
                        systemImage: "exclamationmark.triangle")
                    HStack {
                        Button("Save as new snippet") { recoverDraft() }
                            .accessibilityIdentifier("snippet-recover-button")
                        Button("Discard draft", role: .destructive) { discardDraft() }
                            .accessibilityIdentifier("snippet-discard-button")
                    }
                }
                .padding(GanchoTokens.Spacing.sm)
                .background(.quaternary, in: roundedCard)
                .accessibilityElement(children: .contain)
            }
            TextField("Snippet title", text: $draft.edited.title)
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

            SyntaxTextView(text: $draft.edited.body)
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

            let fields = SnippetTemplate.fields(in: draft.edited.body)
            if !fields.isEmpty {
                fieldStrip(fields)
            }

            snippetFooter(for: snippet)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // ⌘S saves without leaving the editor; as a command it beats the
            // text view's own key handling.
            Button("") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .disabled(draft.requiresRecovery && isSavingDraft)
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
            TextField("Keyword", text: $draft.edited.keyword)
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
                Label("\(draft.edited.body.count) characters", systemImage: "text.alignleft")
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
                .disabled(draft.isMissing)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ActionButton("Copy", systemImage: "doc.on.doc", identifier: "snippet-copy") {
                    SystemPasteboardWriter().write(.text(draft.edited.body), asPlainText: true)
                    model.toasts.show(GanchoToast(message: "Copied"))
                }
                ActionButton("Save", systemImage: "checkmark", identifier: "snippet-save") {
                    save()
                }
                .disabled(draft.isMissing)
                #if DEBUG
                    if CommandLine.arguments.contains("-ui-test-snippet-deletion"),
                        CommandLine.arguments.contains("-use-temp-durable-store"),
                        AppModel.uiTestDefaultsSuiteName() != nil
                    {
                        Button("Remove test source") { simulateSnippetDeletion(id: snippet.id) }
                            .accessibilityIdentifier("snippet-delete-source-button")
                    }
                #endif
            }
        }
    }
}
