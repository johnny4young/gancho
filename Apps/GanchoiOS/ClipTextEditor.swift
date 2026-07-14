import Foundation
import GanchoDesign
import GanchoKit
import SwiftUI

/// Explicit iOS editor for a text-backed clip. The bound durable value changes
/// only after Save succeeds; Cancel and failed writes leave history untouched.
struct ClipTextEditor: View {
    @Binding var text: String
    let kind: ClipContentKind
    let onSave: @MainActor (String) async -> Bool

    @State private var draft: String
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var saveFailed = false

    init(
        text: Binding<String>, kind: ClipContentKind,
        onSave: @escaping @MainActor (String) async -> Bool
    ) {
        _text = text
        self.kind = kind
        self.onSave = onSave
        _draft = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        Section("Content") {
            if isEditing {
                editor
            } else {
                Button("Edit", systemImage: "pencil") { beginEditing() }
                    .accessibilityLabel(Text("Edit content"))
                    .accessibilityIdentifier("detail-edit-content")
                Text(displayText)
                    .font(kind == .code ? .body.monospaced() : .body)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("detail-content")
            }
        }
        .onChange(of: text) { _, newText in
            guard !isEditing else { return }
            draft = newText
        }
    }

    private var editor: some View {
        Group {
            TextEditor(text: $draft)
                .font(kind == .code ? .body.monospaced() : .body)
                .frame(minHeight: 220)
                .accessibilityIdentifier("detail-content-field")
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
                Button("Cancel") { cancel() }
                    .disabled(isSaving)
                    .accessibilityIdentifier("detail-cancel-content")
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || isBlank)
                    .accessibilityIdentifier("detail-save-content")
            }
        }
    }

    private var isBlank: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayText: String {
        text.count > 8000 ? String(text.prefix(8000)) + "\n…" : text
    }

    private func beginEditing() {
        draft = text
        saveFailed = false
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
            text = pending
            draft = pending
            isEditing = false
        }
    }

    private func cancel() {
        draft = text
        saveFailed = false
        isEditing = false
    }
}
