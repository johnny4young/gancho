import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

// MARK: - Keyboard actions

extension ClipPeek {
    /// The keyboard order: the dock's visible verbs, then a secret's actions.
    /// Transforms live behind ⌘T.
    var navActions: [PeekAction] { shownDockActions + secretActions }

    /// The transforms apply to a clip the peek is showing in full; both
    /// checks already rule out a masked one.
    var offersTransforms: Bool {
        (canTransform || canSmartPaste) && !model.preferences.isPrivateModePaused
    }

    /// Paste variants first (the common case), then OCR, Pin, Board and Stack.
    var dockActions: [PeekAction] {
        var actions: [PeekAction] = [
            PeekAction(
                id: "preview-paste", title: pasteTitle,
                symbol: model.pasteTarget.label == .copy ? "doc.on.doc" : "doc.on.clipboard",
                shortTitle: pasteShortTitle, shortcut: "↩"
            ) {
                model.paste(item)
            },
            PeekAction(
                id: "preview-paste-plain", title: "Paste plain", symbol: "doc.plaintext",
                shortTitle: "Plain", shortcut: "⌥↩"
            ) {
                model.paste(item, asPlainText: true)
            }
        ]
        if let convertAction { actions.append(convertAction) }
        // APPENDED, never inserted at 0: `actionIndex` resets to 0 whenever peek
        // takes focus and Return runs `navActions[actionIndex]`, so position 0 IS
        // the default keyboard action. Putting OCR there would silently turn
        // Return on an image clip from Paste into Copy text from image.
        if model.canCopyImageText(item) {
            actions.append(
                PeekAction(
                    id: "image-copy-text", title: "Copy text from image", symbol: "text.viewfinder",
                    shortTitle: "Copy text", shortcut: "⇧⌘C"
                ) { model.copyImageText(item, surface: .peek) })
        }
        actions.append(
            PeekAction(
                id: "preview-pin", title: item.isPinned ? "Unpin" : "Pin",
                symbol: item.isPinned ? "pin.slash" : "pin", shortcut: "⌘P"
            ) { model.togglePin(item) })
        actions.append(
            PeekAction(
                id: "preview-board", title: "Add to board", symbol: "tray", shortTitle: "Board",
                shortcut: "⌘B"
            ) { addToBoard() })
        actions.append(
            PeekAction(
                id: "preview-stack", title: "Add to paste stack", symbol: "square.stack.3d.up",
                shortTitle: "Stack", shortcut: "⌥⌘↩"
            ) { model.pushToStack(item) })
        if let showContext {
            actions.append(
                PeekAction(
                    id: "preview-context", title: "Show context", symbol: "clock",
                    shortTitle: "Context", shortcut: "⌘J"
                ) { showContext() })
        }
        return actions
    }

    private var pasteTitle: LocalizedStringKey {
        switch model.pasteTarget.label {
        case .pasteInto(let app): "Paste into \(app)"
        case .paste: "Paste"
        case .copy: "Copy"
        }
    }

    /// "Paste" once the dock has no room to name the app.
    private var pasteShortTitle: LocalizedStringKey? {
        if case .pasteInto = model.pasteTarget.label { return "Paste" }
        return nil
    }

    /// A colour clip's Convert, a dock action with ⇧↩; its formats open in the result box.
    var convertAction: PeekAction? {
        guard colorValue != nil, !hidesPreview else { return nil }
        return PeekAction(
            id: "preview-convert", title: "Convert", symbol: "arrow.triangle.2.circlepath",
            shortcut: "⇧↩"
        ) {
            actionResult = try? DevActions.run(.convertColor, on: presentedText)
        }
    }

    var canPickColor: Bool {
        item.kind == .image && !hidesPreview && model.thumbnails.cached(for: item) != nil
    }
}
