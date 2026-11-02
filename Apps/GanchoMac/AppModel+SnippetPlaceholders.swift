import AppKit
import ClipboardCore
import GanchoAppCore
import GanchoKit

/// What a snippet's {clipboard} and {cursor} need at insert time.
extension AppModel {
    /// The text for each clipboard placeholder. A protected copy, a secret, a
    /// non-text clip and anything in Private Mode are left out, and a toast
    /// says so rather than letting the blank pass unnoticed.
    func clipboardPlaceholderValues(in body: String) async -> [Int: String] {
        let offsets = SnippetTemplate.clipboardOffsets(in: body)
        guard !offsets.isEmpty else { return [:] }
        var values: [Int: String] = [:]
        if !preferences.isPrivateModePaused {
            for offset in offsets {
                values[offset] =
                    offset == 0 ? liveClipboardText() : await historyText(offset: offset)
            }
        }
        if values.count < offsets.count {
            toasts.show(
                GanchoToast(message: "A clipboard placeholder was left empty.", style: .warning))
        }
        return values
    }

    private func liveClipboardText() -> String? {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        let text = pasteboard.string(forType: .string)
        guard
            case .text(let input) = ClipboardTransformInput.evaluate(
                types: types, text: text, changed: pasteboard.changeCount != before)
        else { return nil }
        return input
    }

    private func historyText(offset: Int) async -> String? {
        ClipboardTransformInput.historyValue(
            try? await grdbForEngines?.historyTextForSnippet(offset: offset))
    }

    /// Gives the target a beat to take the paste, and never sends the arrows
    /// to an app the user has since switched to.
    func moveCaretAfterPaste(by characters: Int, in target: String?) async {
        guard (try? await Task.sleep(for: .milliseconds(150))) != nil, let target,
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target
        else { return }
        pasteBack.moveCaretBack(by: characters)
    }
}
