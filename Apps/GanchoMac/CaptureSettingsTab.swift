import GanchoDesign
import SwiftUI

struct CaptureSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Capture images", isOn: $model.preferences.captureImages)
            Toggle("Capture copied files", isOn: $model.preferences.captureFileReferences)
            Toggle("Keep rich text formatting", isOn: $model.preferences.captureRichText)

            // The editable never-capture list sits with the capture toggles —
            // it's the same question ("what gets captured?"). Its own file: the
            // user's entries, one Add-app menu, and the built-in exclusions
            // folded into a disclosure so the section fits the window.
            DenylistSettingsSection()

            Section("Intelligence") {
                Button("Open Intelligence…") { model.intelligenceWindow.show(model: model) }
                    .accessibilityIdentifier("open-intelligence")
                Text(
                    // swiftlint:disable:next line_length
                    "On-device titles, semantic retrieval, screenshot OCR, and secret detection — each a toggle, all local."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }
}
