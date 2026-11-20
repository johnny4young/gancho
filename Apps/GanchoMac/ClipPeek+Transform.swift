import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension ClipPeek {
    /// The dock's Actions entry: a click or ⌘K opens the action panel.
    var actionsButton: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button {
            // The click itself moved focus into the peek; typing belongs to the search field.
            openActionPanel(returningTo: .search)
        } label: {
            HStack(spacing: 6) {
                Text("Actions").panelFont(size: 12.5, .medium).lineLimit(1)
                KeyCap("⌘K").accessibilityHidden(true)
            }
            .padding(.horizontal, 7)
            .frame(height: PeekActionButton.dockHeight * typeScale)
            .foregroundStyle(GanchoTokens.Palette.ink)
            .overlay(
                shape.strokeBorder(
                    GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .fixedSize()
        // Verbs stay reachable while a transform runs; only new transforms wait.
        .accessibilityValue(Text(verbatim: "⌘K"))
        .accessibilityIdentifier("transform-button")
    }

    /// The action panel, anchored to the peek's top-trailing corner; a click beside it closes it.
    @ViewBuilder var actionPanelLayer: some View {
        if showsActionPanel {
            let actions = dockActions
            ZStack(alignment: .topTrailing) {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { closeActionPanel() }
                    .accessibilityHidden(true)
                PeekActionPanel(
                    groups: panelGroups(actions),
                    title: { transformTitle($0) }, groupTitle: groupTitle,
                    symbol: { transformSymbol($0, dock: actions) },
                    key: { rowKey($0, dock: actions) }, footnote: panelFootnote,
                    isEnabled: canRun,
                    onSelect: { runTransformRow($0, dock: actions) },
                    onClose: { closeActionPanel() }
                )
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                // A reopen during the closing transition would revive the old panel,
                // whose focus task never runs again.
                .id(actionPanelOpenCount)
            }
            .transition(
                GanchoMotion.replace(reduceMotion: reduceMotion)
                    .combined(with: AnyTransition(InertWhileClosing())))
        }
    }

    /// `returnFocus` overrides where the keyboard goes back to; nil keeps where it is now.
    func openActionPanel(returningTo returnFocus: PanelFocus? = nil) {
        guard !showsActionPanel else { return }
        actionPanelReturnFocus = returnFocus ?? focus.wrappedValue ?? .search
        // Released first, or the panel's own focus keeps the search field and takes esc.
        focus.wrappedValue = nil
        actionPanelOpenCount &+= 1
        showsActionPanel = true
    }

    /// Hands the keyboard back to where it was, unless the row just run took it.
    func closeActionPanel(restoringFocus: Bool = true) {
        showsActionPanel = false
        guard restoringFocus else { return }
        Task { @MainActor in
            await Task.yield()
            guard focus.wrappedValue == nil, !isInlineEditing else { return }
            focus.wrappedValue = actionPanelReturnFocus
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

    /// The clip's verbs first, then what it can be turned into.
    private func panelGroups(_ dock: [PeekAction]) -> [TransformGroup] {
        let clip = TransformCatalog.clipGroup(
            dockIDs: dock.map(\.id), markdownLink: linkParts != nil && !hidesPreview,
            deletes: !isInlineEditing)
        return [clip] + (offersTransforms ? transformGroups : [])
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
        case .verb(let verb): verbTitle(verb)
        case .recipes: String(localized: "Text recipes…")
        case .step(let step): String(localized: String.LocalizationValue(step.title))
        case .smartPaste(let action): String(localized: String.LocalizationValue(action.titleKey))
        case .translate(let code):
            String(localized: "Translate to \(LanguageName.localized(code: code))")
        case .describeChange: String(localized: "Describe the change…")
        case .savedPrompt(let prompt): prompt
        }
    }

    private func verbTitle(_ verb: ClipVerb) -> String {
        switch verb {
        case .paste: pasteVerbTitle
        case .pastePlain: String(localized: "Paste plain")
        case .convert: String(localized: "Convert")
        case .stack: String(localized: "Add to paste stack")
        case .pin: String(localized: item.isPinned ? "Unpin" : "Pin")
        case .board: String(localized: "Add to board…")
        case .context: String(localized: "Show context")
        case .imageText: String(localized: "Copy text from image")
        case .markdownLink: String(localized: "Copy as Markdown link")
        case .delete: String(localized: "Delete")
        }
    }

    private var pasteVerbTitle: String {
        switch model.pasteTarget.label {
        case .pasteInto(let app): String(localized: "Paste into \(app)")
        case .paste: String(localized: "Paste")
        case .copy: String(localized: "Copy")
        }
    }

    /// The row's key outside the panel: its dock button's, or ⌫ for Delete.
    private func rowKey(_ row: TransformRow, dock: [PeekAction]) -> String? {
        guard case .verb(let verb) = row else { return nil }
        if verb == .delete { return "⌫" }
        return dock.first { $0.id == verb.dockID }?.shortcut
    }

    /// The on-device extras the panel really offers, for its footer.
    private var panelFootnote: String {
        let rows = offersTransforms ? transformGroups.flatMap(\.rows) : []
        var names: [String] = []
        if rows.contains(.recipes) { names.append(String(localized: "recipes")) }
        if rows.contains(where: {
            switch $0 {
            case .smartPaste, .describeChange, .savedPrompt: true
            default: false
            }
        }) {
            names.append(String(localized: "smart paste"))
        }
        if rows.contains(where: { if case .translate = $0 { true } else { false } }) {
            names.append(String(localized: "translate"))
        }
        return names.formatted(.list(type: .and, width: .narrow))
    }

    private func groupTitle(_ group: TransformGroup) -> Text {
        switch group.kind {
        case .clip: Text("Clip")
        case .clipKind(let clipKind): Text(clipKind.cardName)
        case .text: Text("Text · \(group.rows.count) transforms")
        case .recipes: Text("Recipes")
        case .smartPaste: Text("Smart paste · on-device")
        }
    }

    private func transformSymbol(_ row: TransformRow, dock: [PeekAction]) -> String {
        switch row {
        case .verb(.markdownLink): "link"
        case .verb(.delete): "trash"
        case .verb(let verb): dock.first { $0.id == verb.dockID }?.symbol ?? "circle"
        case .recipes: "list.bullet.rectangle"
        case .step(.text): "textformat"
        case .step(.dev): "chevron.left.forwardslash.chevron.right"
        case .smartPaste(let action): action.symbolName
        case .translate: "globe"
        case .describeChange: "text.bubble"
        case .savedPrompt: "bookmark"
        }
    }

    /// While a transform runs, only clip verbs run; new transforms wait.
    private func canRun(_ row: TransformRow) -> Bool { !isThinking || row.isVerb }

    /// A verb runs what its dock button or key runs.
    private func runTransformRow(_ row: TransformRow, dock: [PeekAction]) {
        guard canRun(row) else { return }
        closeActionPanel(restoringFocus: !row.focusesOwnField)
        switch row {
        case .verb(.markdownLink): copyMarkdownLink()
        case .verb(.delete): if !isInlineEditing { model.delete(item) }
        case .verb(let verb): dock.first { $0.id == verb.dockID }?.run()
        case .recipes:
            recipeRequest = TextRecipeReviewRequest(clipID: item.id)
        case .step(let step):
            actionResult = nil
            transformPipeline = TransformPipeline(steps: [step])
            if case .dev = step {
                model.defaults.set(
                    model.defaults.integer(forKey: "dev-actions-run") + 1,
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

/// The transform output the peek scrolls to when it appears.
enum PeekResultSection: Hashable {
    case pipeline, describe, result
}

extension ClipPeek {
    var shownResult: PeekResultSection? {
        if describeMode { return describedChange == nil ? nil : .describe }
        if !transformPipeline.isEmpty { return .pipeline }
        if let actionResult, !actionResult.isEmpty, !isThinking { return .result }
        return nil
    }

    /// A one-off action's output with its Paste and Copy.
    func resultBox(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            ScrollView {
                Text(result)
                    .accessibilityIdentifier("intelligence-result-text")
                    .panelFont(.body, design: .monospaced)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                ActionButton("Paste", systemImage: "doc.on.clipboard", identifier: "paste-result") {
                    model.pasteText(result)
                }
                ActionButton("Copy result", systemImage: "doc.on.doc", identifier: "copy-result") {
                    SystemPasteboardWriter().write(.text(result), asPlainText: true)
                    model.toasts.show(GanchoToast(message: "Copied"))
                }
            }
        }
    }
}

/// A closing layer must not swallow the clicks meant for the peek under it.
private struct InertWhileClosing: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.allowsHitTesting(phase != .didDisappear)
    }
}

extension TransformRow {
    /// Clip verbs stay runnable while a transform is in flight.
    fileprivate var isVerb: Bool {
        if case .verb = self { return true }
        return false
    }

    /// The board picker, a change request and the recipes sheet take the keyboard.
    fileprivate var focusesOwnField: Bool {
        switch self {
        case .verb(.board), .describeChange, .savedPrompt, .recipes: true
        default: false
        }
    }
}
