import GanchoDesign
import SwiftUI

/// Inline title editor shared by every iOS clip-detail presentation. Drafts
/// stay local until Save succeeds; Cancel and failed writes preserve the last
/// durable title. `prominent` shows the title as the detail's heading, with
/// no section label, and edits it in place.
struct ClipTitleEditor: View {
    let onSave: @MainActor (String) async -> Bool
    var prominent = false

    @State private var presentedTitle: String
    @State private var titleDraft: String
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var saveFailed = false

    init(
        title: String, prominent: Bool = false,
        onSave: @escaping @MainActor (String) async -> Bool
    ) {
        self.onSave = onSave
        self.prominent = prominent
        _presentedTitle = State(initialValue: title)
        _titleDraft = State(initialValue: title)
    }

    var body: some View {
        if prominent {
            Section { editor.listRowBackground(isEditing ? nil : Color.clear) }
        } else {
            Section("Title") { editor }
        }
    }

    @ViewBuilder private var editor: some View {
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
                    .ganchoButtonStyle(.primary)
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
                    .font(prominent ? .title3.weight(.heavy) : .body)
                    .accessibilityIdentifier("detail-title")
                Spacer()
                Button {
                    titleDraft = presentedTitle
                    saveFailed = false
                    isEditing = true
                } label: {
                    if prominent {
                        Image(systemName: "pencil")
                    } else {
                        Label("Edit", systemImage: "pencil")
                    }
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
