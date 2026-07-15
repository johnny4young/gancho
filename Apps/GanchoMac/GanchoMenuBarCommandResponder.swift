import AppKit

/// Performs menu-bar commands against the main app model.
///
/// The external helper routes commands here through content-free distributed
/// notifications, keeping the full clipboard history and command payloads
/// inside the main app process. The in-process status-item fallback calls the
/// same responder directly, so both menu-bar implementations stay aligned.
@MainActor
extension GanchoMenuBarCommand {
    func perform(on model: AppModel) {
        switch self {
        case .library:
            model.libraryWindow.show(model: model)
        case .openPanel:
            model.panel.show(model: model)
        case .toggleCapture:
            model.togglePause()
        case .togglePrivateMode:
            model.togglePrivateMode()
        case .ignoreNextCopy:
            model.ignoreNextCopy()
        case .settings:
            model.settingsWindow.show(model: model)
        case .welcome:
            model.welcomeWindow.show(model: model)
        case .privacyCenter:
            model.privacyCenterWindow.show(model: model)
        case .wrapped:
            model.exportWrapped()
        case .fixClipboardAccess:
            model.permissionWindow.show(model: model)
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }
}
