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
            paste: { model.pasteText($0) },
            copy: { result in
                SystemPasteboardWriter().write(.text(result), asPlainText: true)
                model.toasts.show(GanchoToast(message: "Copied"))
            },
            close: closeTransform)
    }

    /// What ⇧⏎ pastes: the pipeline's result, or the result box's.
    var pendingResult: String? {
        if !transformPipeline.isEmpty,
            case .text(let result) = transformPipeline.run(on: presentedText)
        {
            return result
        }
        guard let actionResult, !actionResult.isEmpty else { return nil }
        return actionResult
    }

    func closeTransform() {
        transformPipeline = TransformPipeline()
        actionResult = nil
    }

    private var transformGroups: [TransformGroup] {
        guard canTransform || canSmartPaste else { return [] }
        let groups = TransformCatalog.groups(
            kind: item.kind,
            includesRecipes: isTextEditable && !hidesPreview && model.fullStore != nil,
            smartPaste: canSmartPaste, modelAvailable: model.smartPasteModelAvailable,
            translationCodes: translationTargets.filter(\.isAvailable).map(\.code))
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
        }
    }
}
