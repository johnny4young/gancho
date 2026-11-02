import AppKit
import ClipboardCore
import Foundation
import GanchoAppCore
import GanchoDesign
import GanchoKit

/// The copy-time action HUD: a color, a web link or a one-time code just
/// copied gets one or two actions without opening the panel.
extension AppModel {
    func offerCopyActions(
        for outcome: ClipIngestionCoordinator.Outcome, capture: PasteboardCapture
    ) {
        guard
            let action = CopyActionPolicy.action(
                for: outcome.item, isNew: outcome.isNew, text: capture.textRepresentation,
                switches: preferences.copyActions,
                privateMode: preferences.isPrivateModePaused, sharingScreen: sharingAppName != nil)
        else { return }
        copyHUD.show(hud(for: action, item: outcome.item), below: toasts.visibleFrame)
    }

    private func hud(for action: CopyAction, item: ClipItem) -> CopyHUD {
        switch action {
        case .color(let color):
            CopyHUD(
                tile: .swatch(color), title: "Color · \(color.hex)",
                actions: [
                    CopyHUDAction(id: "rgb", title: "Copy as rgb()", isPrimary: true) {
                        [weak self] in self?.copyColorFormat(color.rgb, label: "RGB")
                    },
                    CopyHUDAction(id: "hsl", title: "Copy as HSL") { [weak self] in
                        self?.copyColorFormat(color.hsl, label: "HSL")
                    }
                ])
        case .link(let url):
            CopyHUD(
                tile: .symbol("link"),
                title:
                    "Link · \(ClipLinkParts(text: url.absoluteString)?.host ?? url.host() ?? "")",
                actions: [
                    CopyHUDAction(id: "open", title: "Open", isPrimary: true) {
                        NSWorkspace.shared.open(url)
                    }
                ])
        case .oneTimeCode:
            CopyHUD(
                tile: .symbol("lock.fill", danger: true),
                title: "One-time code · \(ClipSafePresentation.masked)",
                actions: [
                    CopyHUDAction(id: "forget", title: "Forget now", isPrimary: true) {
                        [weak self] in self?.forgetCopiedCode(item)
                    }
                ])
        }
    }

    /// Deletes the code's clip at once, with its sync tombstone; the copy on
    /// the clipboard stays, so it can still be pasted.
    private func forgetCopiedCode(_ item: ClipItem) {
        Task { @MainActor in
            let outcome = await ClipDeletionWorkflow().delete(
                ids: [item.id], store: store, syncStore: fullStore, engine: syncController.engine,
                syncEnabled: syncController.isEnabled)
            reportDeletionFailure(outcome)
            await refreshRecents()
            notifyStoreChanged(for: .clips)
            guard case .deleted = outcome else { return }
            copyHUD.show(CopyHUD(tile: .symbol("checkmark"), title: "Forgotten"))
        }
    }

    /// `-seed-copy-actions <color|link|code>`: copy actions on, then one
    /// capture of that kind through the real ingest path.
    func seedCopyActionsIfRequested() -> Task<Void, Never>? {
        #if DEBUG
            let arguments = CommandLine.arguments
            guard let index = arguments.firstIndex(of: "-seed-copy-actions"),
                arguments.indices.contains(index + 1),
                arguments.contains("-use-temp-durable-store"),
                arguments.contains("-ui-test-paste-sink")
            else { return nil }
            let samples = ["color": "#008080", "link": "https://gancho.app/docs", "code": "482 913"]
            guard let text = samples[arguments[index + 1]] else { return nil }
            preferences.copyActions = CopyActionSwitches(isEnabled: true)
            return ingest(
                PasteboardCapture(payload: .text(text), sourceAppBundleID: "com.apple.Safari"))
        #else
            return nil
        #endif
    }
}
