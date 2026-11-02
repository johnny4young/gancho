import AppKit
import GanchoAppCore
import GanchoKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// One optional global shortcut per saved recipe; no default.
    static func recipe(_ id: UUID) -> Self { Self("recipe-\(id.uuidString)") }
}

extension AppModel {
    /// Remembers what ⌃⌘V repeats: the steps of the transform that just delivered.
    func rememberLastTransform(_ actionIDs: [String]) {
        guard !actionIDs.isEmpty else { return }
        LastTransform(actionIDs: actionIDs).save(to: defaults)
    }

    func pasteClipboardThroughLastTransform() {
        guard let last = LastTransform.load(from: defaults) else {
            toasts.show(GanchoToast(message: "Paste or copy a transform result first."))
            return
        }
        pasteClipboard(through: last.recipe)
    }

    /// Runs the clipboard's plain text through a recipe and pastes the result.
    /// Protected copies and detected secrets are refused; nothing is logged.
    func pasteClipboard(through recipe: TextRecipe) {
        guard !preferences.isPrivateModePaused else {
            toasts.show(GanchoToast(message: "Private Mode is on, so nothing was transformed."))
            return
        }
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        let text = pasteboard.string(forType: .string)
        let input: String
        switch ClipboardTransformInput.evaluate(
            types: types, text: text, changed: pasteboard.changeCount != before)
        {
        case .text(let text): input = text
        case .refused(let refusal):
            toasts.show(GanchoToast(message: Self.message(for: refusal), style: .warning))
            return
        }
        Task {
            do {
                let output = try await TextRecipeExecutor().run(recipe, on: input)
                rememberLastTransform(recipe.steps.map(\.actionID))
                pasteText(output)
            } catch {
                toasts.show(
                    GanchoToast(message: "That transform can’t change this text.", style: .warning))
            }
        }
    }

    /// Registers each saved recipe's shortcut once; a handler looks the recipe
    /// up when it fires, so a deleted or edited recipe never runs stale steps.
    func registerRecipeShortcuts() async {
        guard let store = textRecipeStore,
            let records = try? await store.textRecipes()
        else { return }
        for record in records {
            guard let recipe = record.recipe, !registeredRecipeShortcuts.contains(recipe.id) else {
                continue
            }
            registeredRecipeShortcuts.insert(recipe.id)
            let id = recipe.id
            KeyboardShortcuts.onKeyUp(for: .recipe(id)) { [weak self] in
                self?.runRecipeShortcut(id)
            }
        }
    }

    /// Forgets a deleted recipe's shortcut so its keys are free again.
    func recipeDeleted(_ id: UUID) {
        KeyboardShortcuts.reset(.recipe(id))
    }

    private func runRecipeShortcut(_ id: UUID) {
        Task {
            guard let store = textRecipeStore,
                let recipe = try? await store.textRecipes().first(where: { $0.id == id.uuidString }
                )?
                .recipe
            else { return }
            pasteClipboard(through: recipe)
        }
    }

    private static func message(
        for refusal: ClipboardTransformInput.Refusal
    ) -> LocalizedStringResource {
        switch refusal {
        case .protectedType: "This clipboard item is protected, so it wasn’t transformed."
        case .noText: "The clipboard has no text to transform."
        case .secret: "The clipboard holds a secret, so it wasn’t transformed."
        case .tooLarge: "The clipboard text is too large to transform."
        case .changed: "The clipboard changed while it was read. Try again."
        }
    }
}

extension AppModel {
    /// "Describe the change" needs the model and a text that fits one request.
    func canDescribeChange(_ text: String) -> Bool {
        #if DEBUG
            if Self.usesDescribeChangeFixture { return true }
        #endif
        return smartPasteModelAvailable && intelligenceFacade.fitsDescribeChange(text)
    }

    /// The rewrite of `text` the user asked for in words, on device; nil on failure.
    func describeChange(_ text: String, change: String) async -> String? {
        #if DEBUG
            // UI tests have no model: a fixed, visible rewrite stands in for it.
            if Self.usesDescribeChangeFixture {
                return text.replacingOccurrences(of: "improve", with: "ship")
            }
        #endif
        return await intelligenceFacade.describeChange(text, change: change)
    }

    var savedChangePrompts: [String] { SavedPrompts.load(from: defaults).prompts }

    /// False when the request can't be kept (too long, or it holds a secret).
    @discardableResult
    func saveChangePrompt(_ prompt: String) -> Bool {
        var saved = SavedPrompts.load(from: defaults)
        guard saved.add(prompt) else { return false }
        saved.save(to: defaults)
        return true
    }

    #if DEBUG
        private static var usesDescribeChangeFixture: Bool {
            CommandLine.arguments.contains("-ui-test-describe-change")
                && CommandLine.arguments.contains("-use-temp-durable-store")
        }
    #endif
}
