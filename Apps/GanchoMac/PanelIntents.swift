import AppIntents

/// Mac surface intents over the SAME AppModel the UI drives (registered via
/// AppDependencyManager at launch — no logic forks).
struct OpenPanelIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Gancho Panel"
    static let description = IntentDescription("Opens the clipboard history panel.")
    static let openAppWhenRun = true

    @Dependency
    private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        model.panel.show(model: model)
        return .result()
    }
}

struct TogglePrivateModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Private Mode"
    static let description = IntentDescription(
        "Pauses or resumes clipboard capture (private mode).")

    @Dependency
    private var model: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        model.togglePrivateMode()
        let active = model.preferences.isPrivateModePaused
        return .result(dialog: active ? "Private mode on." : "Private mode off.")
    }
}
