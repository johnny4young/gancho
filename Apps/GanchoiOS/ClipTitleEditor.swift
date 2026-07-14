import GanchoDesign
import SwiftUI

/// Inline title editor shared by every iOS clip-detail presentation. Drafts
/// stay local until Save succeeds; Cancel and failed writes preserve the last
/// durable title.
struct ClipTitleEditor: View {
    let onSave: @MainActor (String) async -> Bool

    @State private var presentedTitle: String
    @State private var titleDraft: String
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var saveFailed = false

    init(title: String, onSave: @escaping @MainActor (String) async -> Bool) {
        self.onSave = onSave
        _presentedTitle = State(initialValue: title)
        _titleDraft = State(initialValue: title)
    }

    var body: some View {
        Section("Title") {
            if isEditing {
                TextField("Title", text: $titleDraft)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit { save() }
                    .accessibilityIdentifier("detail-title-field")
                HStack {
                    Button("Cancel") { cancel() }
                        .disabled(isSaving)
                        .accessibilityIdentifier("detail-cancel-title")
                    Spacer()
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                        .accessibilityIdentifier("detail-save-title")
                }
            } else {
                HStack {
                    Text(presentedTitle.isEmpty ? String(localized: "Untitled") : presentedTitle)
                        .foregroundStyle(
                            presentedTitle.isEmpty
                                ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
                        )
                        .accessibilityIdentifier("detail-title")
                    Spacer()
                    Button("Edit", systemImage: "pencil") {
                        titleDraft = presentedTitle
                        saveFailed = false
                        isEditing = true
                    }
                    .accessibilityLabel(Text("Edit title"))
                    .accessibilityIdentifier("detail-edit-title")
                }
            }
            if saveFailed {
                Text("Couldn’t save the title.")
                    .font(.caption)
                    .foregroundStyle(GanchoTokens.Palette.danger)
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        saveFailed = false
        let draft = titleDraft
        Task {
            let saved = await onSave(draft)
            isSaving = false
            guard saved else {
                saveFailed = true
                return
            }
            let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            presentedTitle = normalized
            titleDraft = normalized
            isEditing = false
        }
    }

    private func cancel() {
        titleDraft = presentedTitle
        saveFailed = false
        isEditing = false
    }
}
