import AppKit
import ClipboardCore
import Combine
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

struct TextRecipeReviewRequest: Identifiable {
    let id = UUID()
    let clipID: UUID
}

struct TextRecipeReview: View {
    let clipID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var records: [StoredTextRecipe] = []
    @State private var draft: TextRecipe?
    @State private var savedDraft: TextRecipe?
    @State private var selectedID = ""
    @State private var pendingSelection: String?
    @State private var actionID = TextActionCatalog.normalizeNewlines
    @State private var part: CombinedTextPart?
    @State private var result: String?
    @State private var revision = 0
    @State private var operation: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var loading = true
    @State private var failed = false
    @State private var clipboardChanged = false
    @State private var confirmDiscard = false

    private var storage: (any TextRecipeStoring)? { model.textRecipeStore }
    private var dirty: Bool { draft != savedDraft }
    private var input: String? {
        guard case .text(let text) = part?.content else { return nil }
        return text
    }
    private var valid: Bool { draft.map { (try? $0.validate()) != nil } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Text recipes").panelFont(.headline)
            Text("Local recipes. Originals stay unchanged; copying is explicit.").panelFont(
                .caption)
            Text(
                "Up to eight steps and 1 MiB per input and result; context formatting allows 64 KiB."
            ).panelFont(.caption)
            HStack {
                Picker("Recipe", selection: Binding(get: { selectedID }, set: { select($0) })) {
                    Text("Choose a recipe").tag("")
                    ForEach(records) { record in
                        Text(title(record)).tag(record.id)
                    }
                }.accessibilityIdentifier("text-recipe-picker")
                Button("New recipe") { selectNew() }.disabled(dirty || loading || operation != nil)
                    .accessibilityIdentifier("text-recipe-new")
                Button("Delete") { remove() }.disabled(selectedID.isEmpty || operation != nil)
                    .accessibilityIdentifier("text-recipe-delete")
            }
            if draft != nil {
                editor
            } else if !selectedID.isEmpty {
                Text("This definition is damaged. Other recipes are unaffected; you can delete it.")
                    .foregroundStyle(.orange)
            }
            if !model.preferences.isPrivateModePaused, let input {
                HStack(alignment: .top) {
                    preview("Before", input, identifier: "text-recipe-before")
                    preview("After", result ?? "", identifier: "text-recipe-after")
                }
                Text("Previews show up to 8,000 characters. Copy includes the complete result.")
                    .panelFont(.caption).foregroundStyle(.secondary)
            } else if !loading {
                Text("This clip is unavailable, protected or not text-backed.").foregroundStyle(
                    .orange)
            }
            if failed {
                Text(
                    "Could not complete this operation. Check the definition, sizes and clip availability, then retry."
                )
                .foregroundStyle(.red).panelFont(.caption)
            }
            if clipboardChanged {
                Text("The clipboard changed. Review the result and choose Copy result again.")
                    .foregroundStyle(.orange).panelFont(.caption)
            }
            HStack {
                Button("Cancel") {
                    cancel()
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("text-recipe-cancel")
                Spacer()
                if loading || operation != nil { ProgressView().controlSize(.small) }
                Button("Run recipe") { run() }.disabled(!valid || input == nil || operation != nil)
                    .accessibilityIdentifier("text-recipe-run")
                Button("Copy result") { copy() }.keyboardShortcut(.defaultAction)
                    .disabled(result == nil || operation != nil)
                    .accessibilityIdentifier("text-recipe-copy")
            }
        }.padding(20).frame(minWidth: 680, idealWidth: 680, minHeight: 560)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("text-recipe-review")
            .task { await load() }
            .confirmationDialog("Discard unsaved recipe changes?", isPresented: $confirmDiscard) {
                Button("Discard", role: .destructive) {
                    if let pendingSelection { applySelection(pendingSelection) }
                    pendingSelection = nil
                }
                Button("Cancel", role: .cancel) { pendingSelection = nil }
            }
            .onChange(of: draft) { _, _ in cancel() }
            .onChange(of: model.preferences.isPrivateModePaused) { _, paused in
                if paused {
                    cancel()
                    dismiss()
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSWindow.didChangeOcclusionStateNotification)
            ) { _ in
                if !model.panel.isVisible {
                    cancel()
                    part = nil
                    dismiss()
                }
            }
            .onDisappear {
                cancel()
                part = nil
                result = nil
                draft = nil
                savedDraft = nil
            }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "Recipe name",
                text: Binding(
                    get: { draft?.name ?? "" }, set: { draft?.name = $0 })
            )
            .accessibilityIdentifier("text-recipe-name")
            ForEach(Array((draft?.steps ?? []).enumerated()), id: \.element.id) { index, step in
                HStack {
                    Text(actionTitle(step)).lineLimit(1)
                    Spacer()
                    Button("Move up") { move(index, by: -1) }.disabled(index == 0)
                        .accessibilityIdentifier("text-recipe-move-up-button")
                    Button("Move down") { move(index, by: 1) }
                        .accessibilityIdentifier("text-recipe-move-down-button")
                        .disabled(index + 1 == draft?.steps.count)
                    Button("Remove") { draft?.steps.remove(at: index) }
                        .accessibilityIdentifier("text-recipe-remove-step-button")
                }.panelFont(.caption)
            }
            HStack {
                Picker("Action", selection: $actionID) {
                    ForEach(TextActionCatalog.descriptors) { descriptor in
                        Text(LocalizedStringKey(descriptor.title)).tag(descriptor.id)
                    }
                }.accessibilityIdentifier("text-recipe-action-picker")
                Button("Add step") { draft?.steps.append(TextActionStep(actionID: actionID)) }
                    .disabled((draft?.steps.count ?? 0) >= TextRecipe.maximumSteps)
                    .accessibilityIdentifier("text-recipe-add-step")
                Button("Save recipe") { save() }.disabled(!valid || !dirty || storage == nil)
                    .accessibilityIdentifier("text-recipe-save")
            }
            if !valid {
                Text(
                    "Use a name of up to 80 characters and one to eight supported steps. Unknown versions cannot run."
                )
                .foregroundStyle(.orange).panelFont(.caption)
            }
        }.disabled(operation != nil)
    }
    private func preview(
        _ title: LocalizedStringKey, _ text: String, identifier: String
    ) -> some View {
        VStack(alignment: .leading) {
            Text(title).panelFont(.subheadline)
            ScrollView {
                Text(verbatim: TextRecipePreview.make(text)).panelFont(.body).textSelection(
                    .disabled
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
        }.frame(maxWidth: .infinity, minHeight: 120, maxHeight: 180)
    }
    private func title(_ record: StoredTextRecipe) -> String {
        guard let recipe = record.recipe else { return String(localized: "Damaged recipe") }
        if TextRecipePresets.all.contains(where: { $0.id == recipe.id && $0.name == recipe.name }) {
            return String(localized: String.LocalizationValue(recipe.name))
        }
        return recipe.name
    }
    private func actionTitle(_ step: TextActionStep) -> String {
        guard
            let descriptor = TextActionCatalog.descriptors.first(where: { $0.id == step.actionID })
        else {
            return String(localized: "Unsupported action")
        }
        return String(localized: String.LocalizationValue(descriptor.title))
    }
    private func cancel() {
        generation = UUID()
        operation?.cancel()
        operation = nil
        result = nil
        clipboardChanged = false
    }
    private func select(_ id: String) {
        guard operation == nil else { return }
        if dirty {
            pendingSelection = id
            confirmDiscard = true
        } else {
            applySelection(id)
        }
    }
    private func applySelection(_ id: String) {
        cancel()
        selectedID = id
        draft = records.first(where: { $0.id == id })?.recipe
        savedDraft = draft
    }
    private func selectNew() {
        cancel()
        selectedID = ""
        savedDraft = nil
        draft = TextRecipe(name: "", steps: [TextActionStep(actionID: actionID)])
    }
    private func move(_ index: Int, by offset: Int) {
        guard var recipe = draft, recipe.steps.indices.contains(index + offset) else { return }
        recipe.steps.swapAt(index, index + offset)
        draft = recipe
    }
    private func load() async {
        let request = generation
        defer { loading = false }
        do {
            guard let storage, let reader = model.textReuseReader else {
                failed = true
                return
            }
            let loadedRecords = try await storage.textRecipes()
            let loadedPart = try await CombinedTextService().load(ids: [clipID], from: reader).first
            guard !Task.isCancelled, generation == request,
                !model.preferences.isPrivateModePaused, !model.isDeletionPending(clipID)
            else { return }
            records = loadedRecords
            part = loadedPart
            if selectedID.isEmpty, !dirty, let first = records.first { applySelection(first.id) }
        } catch is CancellationError {} catch {
            guard !Task.isCancelled, generation == request else { return }
            failed = true
        }
    }
    private func save() {
        guard let draft, let storage else { return }
        failed = false
        let request = generation
        operation = Task {
            do {
                try await storage.saveTextRecipe(draft)
                let refreshed = try await storage.textRecipes()
                guard !Task.isCancelled, generation == request else { return }
                records = refreshed
                selectedID = draft.id.uuidString
                savedDraft = draft
                operation = nil
            } catch is CancellationError {} catch {
                guard !Task.isCancelled, generation == request else { return }
                failed = true
                operation = nil
            }
        }
    }
    private func remove() {
        guard let storage else { return }
        let id = selectedID
        cancel()
        failed = false
        let request = generation
        operation = Task {
            do {
                try await storage.deleteTextRecipe(id: id)
                let refreshed = try await storage.textRecipes()
                guard !Task.isCancelled, generation == request else { return }
                records = refreshed
                operation = nil
                applySelection("")
            } catch is CancellationError {} catch {
                guard !Task.isCancelled, generation == request else { return }
                failed = true
                operation = nil
            }
        }
    }
    private func run() {
        guard let draft, let input else { return }
        cancel()
        failed = false
        revision = NSPasteboard.general.changeCount
        let request = generation
        operation = Task {
            do {
                let output = try await TextRecipeExecutor().run(draft, on: input)
                guard !Task.isCancelled, generation == request else { return }
                result = output
                operation = nil
            } catch {
                guard !Task.isCancelled, generation == request else { return }
                failed = true
                operation = nil
            }
        }
    }
    private func copy() {
        guard let result, let part, let reader = model.textReuseReader else { return }
        failed = false
        let request = generation
        operation = Task {
            do {
                let outcome = try await TextRecipeDelivery.copy(
                    result: result, expected: part, from: reader,
                    clipboardUnchanged: { NSPasteboard.general.changeCount == revision },
                    isAllowed: {
                        !model.preferences.isPrivateModePaused && !model.isDeletionPending(clipID)
                    },
                    write: { text in
                        #if DEBUG
                            if !CommandLine.arguments.contains("-ui-test-paste-sink") {
                                SystemPasteboardWriter().write(.text(text), asPlainText: true)
                            }
                        #else
                            SystemPasteboardWriter().write(.text(text), asPlainText: true)
                        #endif
                    })
                try Task.checkCancellation()
                operation = nil
                switch outcome {
                case .copied: dismiss()
                case .clipboardChanged:
                    clipboardChanged = true
                    revision = NSPasteboard.general.changeCount
                case .selectionChanged, .blocked:
                    cancel()
                    failed = true
                }
            } catch is CancellationError {} catch {
                guard !Task.isCancelled, generation == request else { return }
                failed = true
                operation = nil
            }
        }
    }
}
