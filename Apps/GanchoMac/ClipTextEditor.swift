import Foundation
import GanchoDesign
import GanchoKit
import SwiftUI

/// Explicit editor for a text-backed clip. The binding changes only after the
/// durable Save callback succeeds; typing and Cancel never mutate history.
struct ClipTextEditor: View {
    @Binding var text: String
    let kind: ClipContentKind
    let onEditingChanged: @MainActor (Bool) -> Void
    let onSave: @MainActor (String) async -> Bool

    @State private var draft: String
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var isActive = false

    init(
        text: Binding<String>, kind: ClipContentKind,
        onEditingChanged: @escaping @MainActor (Bool) -> Void,
        onSave: @escaping @MainActor (String) async -> Bool
    ) {
        _text = text
        self.kind = kind
        self.onEditingChanged = onEditingChanged
        self.onSave = onSave
        _draft = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack {
                Text("Content")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !isEditing {
                    Button("Edit", systemImage: "pencil") { beginEditing() }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Edit content"))
                        .accessibilityIdentifier("preview-edit-content")
                }
            }

            if isEditing {
                editor
            } else {
                ScrollView {
                    Text(highlighted)
                        .font(kind == .code ? .body.monospaced() : .body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("preview-content")
                }
                .frame(maxHeight: 200)
            }
        }
        .onChange(of: text) { _, newText in
            guard !isEditing else { return }
            draft = newText
        }
        .onAppear { isActive = true }
        .onDisappear {
            isActive = false
            if isEditing { onEditingChanged(false) }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            TextEditor(text: $draft)
                .font(kind == .code ? .body.monospaced() : .body)
                .frame(minHeight: 160, maxHeight: 220)
                .padding(GanchoTokens.Spacing.xxs)
                .background(.quaternary.opacity(0.45))
                .clipShape(
                    RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                .accessibilityIdentifier("preview-content-field")
            if isBlank {
                Text("Content can’t be empty.")
                    .font(.caption)
                    .foregroundStyle(GanchoTokens.Palette.danger)
            } else if saveFailed {
                Text("Couldn’t save the content.")
                    .font(.caption)
                    .foregroundStyle(GanchoTokens.Palette.danger)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { cancel() }
                    .disabled(isSaving)
                    .accessibilityIdentifier("preview-cancel-content")
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || isBlank)
                    .accessibilityIdentifier("preview-save-content")
            }
        }
    }

    private var isBlank: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayText: String {
        text.count > 4000 ? String(text.prefix(4000)) + "\n…" : text
    }

    private var highlighted: AttributedString {
        var attributed = AttributedString(displayText)
        guard kind == .code, displayText.count <= 20_000 else { return attributed }
        for token in GanchoSyntax.tokens(in: displayText) {
            let lower = displayText.distance(
                from: displayText.startIndex, to: token.range.lowerBound)
            let upper = displayText.distance(
                from: displayText.startIndex, to: token.range.upperBound)
            let lo = attributed.index(attributed.startIndex, offsetByCharacters: lower)
            let hi = attributed.index(attributed.startIndex, offsetByCharacters: upper)
            attributed[lo..<hi].foregroundColor = GanchoTokens.Syntax.color(for: token.kind)
        }
        return attributed
    }

    private func beginEditing() {
        draft = text
        saveFailed = false
        onEditingChanged(true)
        isEditing = true
    }

    private func save() {
        guard !isSaving, !isBlank else { return }
        isSaving = true
        saveFailed = false
        let pending = draft
        Task {
            let saved = await onSave(pending)
            isSaving = false
            guard saved else {
                saveFailed = true
                return
            }
            // Selection can move while the durable write is in flight. A
            // replaced editor must never publish its old draft into the new
            // clip's binding.
            guard isActive else { return }
            text = pending
            draft = pending
            isEditing = false
            onEditingChanged(false)
        }
    }

    private func cancel() {
        draft = text
        saveFailed = false
        isEditing = false
        onEditingChanged(false)
    }
}
