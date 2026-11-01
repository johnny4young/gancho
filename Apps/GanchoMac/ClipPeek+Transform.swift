import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension ClipPeek {
    /// The one Transform entry: ⌘T or a click opens the filterable list.
    var transformButton: some View {
        Button {
            showsTransformPopover.toggle()
        } label: {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                Image(systemName: "wand.and.sparkles")
                Text("Transform")
                Text(verbatim: "⌘T")
                    .panelFont(.caption2, design: .monospaced)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .panelFont(.caption2)
            }
            .panelFont(.body, .medium)
            .foregroundStyle(GanchoTokens.Palette.accentInk)
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .padding(.vertical, GanchoTokens.Spacing.xxs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        .disabled(isThinking)
        .accessibilityIdentifier("transform-button")
        .popover(isPresented: $showsTransformPopover, arrowEdge: .bottom) {
            PeekTransformPopover(
                groups: transformGroups, title: transformTitle, groupTitle: groupTitle,
                symbol: transformSymbol, onSelect: runTransformRow)
        }
        .sheet(item: $recipeRequest) { request in
            TextRecipeReview(clipID: request.clipID).environment(model)
        }
    }

    var pipelineSection: some View {
        PeekTransformPipeline(
            pipeline: $transformPipeline, source: presentedText,
            availableSteps: TransformCatalog.steps(for: item.kind),
            title: { String(localized: String.LocalizationValue($0.title)) },
            paste: { result in
                rememberPipeline()
                model.pasteText(result)
            },
            copy: { result in
                rememberPipeline()
                SystemPasteboardWriter().write(.text(result), asPlainText: true)
                model.toasts.show(GanchoToast(message: "Copied"))
            },
            saveRecipe: { saveRecipe(named: $0) },
            close: closeTransform, isEditing: $isEditingTransformField)
    }

    /// What ⇧⏎ pastes: the pipeline's result, or the result box's.
    var pendingResult: String? {
        guard !hidesPreview else { return nil }
        if describeMode { return describedChange?.output }
        if !transformPipeline.isEmpty,
            case .text(let result) = transformPipeline.run(on: presentedText)
        {
            return result
        }
        guard let actionResult, !actionResult.isEmpty else { return nil }
        return actionResult
    }

    /// The pipeline that just delivered is what ⌃⌘V repeats.
    func rememberPipeline() {
        model.rememberLastTransform(transformPipeline.steps.map(\.recipeActionID))
    }

    private func saveRecipe(named name: String) {
        let recipe = transformPipeline.recipe(named: name)
        Task {
            guard let store = model.textRecipeStore else { return }
            do {
                try await store.saveTextRecipe(recipe)
                await model.registerRecipeShortcuts()
                model.toasts.show(GanchoToast(message: "Saved as a recipe"))
            } catch {
                model.toasts.show(
                    GanchoToast(message: "Couldn’t save the recipe.", style: .warning))
            }
        }
    }

    func closeTransform() {
        transformPipeline = TransformPipeline()
        actionResult = nil
        describeMode = false
        describedChange = nil
        describeRequest = UUID()
        isThinking = false
    }

    var describeSection: some View {
        PeekDescribeChange(
            result: describedChange, isThinking: isThinking,
            savedPrompts: model.savedChangePrompts,
            run: runDescribe,
            paste: { model.pasteText($0) },
            copy: { result in
                SystemPasteboardWriter().write(.text(result), asPlainText: true)
                model.toasts.show(GanchoToast(message: "Copied"))
            },
            savePrompt: { prompt in
                if model.saveChangePrompt(prompt) {
                    model.toasts.show(GanchoToast(message: "Prompt saved"))
                } else {
                    model.toasts.show(
                        GanchoToast(
                            message:
                                "This prompt can’t be saved: it holds a secret or is too long.",
                            style: .warning))
                }
            },
            close: closeTransform, isEditing: $isEditingTransformField)
    }

    /// Runs one change request; a newer request or a close drops a late answer.
    func runDescribe(_ prompt: String) {
        let request = UUID()
        describeRequest = request
        let input = presentedText
        describedChange = nil
        isThinking = true
        Task {
            let output = await model.describeChange(input, change: prompt)
            guard describeRequest == request else { return }
            isThinking = false
            if let output {
                describedChange = DescribedChange(prompt: prompt, input: input, output: output)
            } else {
                model.toasts.show(
                    GanchoToast(message: "Couldn’t run that — try again.", style: .warning))
            }
        }
    }

    private var transformGroups: [TransformGroup] {
        guard canTransform || canSmartPaste else { return [] }
        let groups = TransformCatalog.groups(
            kind: item.kind,
            includesRecipes: isTextEditable && !hidesPreview && model.fullStore != nil,
            smartPaste: canSmartPaste, modelAvailable: model.smartPasteModelAvailable,
            translationCodes: translationTargets.filter(\.isAvailable).map(\.code),
            describeChange: model.canDescribeChange(presentedText),
            savedPrompts: model.savedChangePrompts)
        // A clip that only reaches Smart paste (a colour) keeps its transforms off.
        return canTransform ? groups : groups.filter { $0.kind == .smartPaste }
    }

    private func transformTitle(_ row: TransformRow) -> String {
        switch row {
        case .recipes: String(localized: "Text recipes…")
        case .step(let step): String(localized: String.LocalizationValue(step.title))
        case .smartPaste(let action): String(localized: String.LocalizationValue(action.titleKey))
        case .translate(let code):
            String(localized: "Translate to \(LanguageName.localized(code: code))")
        case .describeChange: String(localized: "Describe the change…")
        case .savedPrompt(let prompt): prompt
        }
    }

    private func groupTitle(_ kind: TransformGroup.Kind) -> Text {
        switch kind {
        case .clipKind(let clipKind): Text(clipKind.cardName)
        case .text: Text("Text")
        case .recipes: Text("Recipes")
        case .smartPaste: Text("Smart paste · on-device")
        }
    }

    private func transformSymbol(_ row: TransformRow) -> String {
        switch row {
        case .recipes: "list.bullet.rectangle"
        case .step(.text): "textformat"
        case .step(.dev): "chevron.left.forwardslash.chevron.right"
        case .smartPaste(let action): action.symbolName
        case .translate: "globe"
        case .describeChange: "text.bubble"
        case .savedPrompt: "bookmark"
        }
    }

    private func runTransformRow(_ row: TransformRow) {
        showsTransformPopover = false
        switch row {
        case .recipes:
            recipeRequest = TextRecipeReviewRequest(clipID: item.id)
        case .step(let step):
            actionResult = nil
            transformPipeline = TransformPipeline(steps: [step])
            if case .dev = step {
                UserDefaults.standard.set(
                    UserDefaults.standard.integer(forKey: "dev-actions-run") + 1,
                    forKey: "dev-actions-run")
            }
        case .smartPaste(let action):
            transformPipeline = TransformPipeline()
            runSmartPaste(action)
        case .translate(let code):
            transformPipeline = TransformPipeline()
            runTranslate(to: Locale.Language(identifier: code))
        case .describeChange:
            closeTransform()
            describeMode = true
        case .savedPrompt(let prompt):
            closeTransform()
            describeMode = true
            runDescribe(prompt)
        }
    }
}
