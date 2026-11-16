import ClipboardCore
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

            Section {
                ConcealedRuleCard()
            }

            Section {
                Toggle(isOn: $model.preferences.mergeDoubleCopies) {
                    Text("Merge double copies")
                    Text("Press ⌘C twice on a selection to add it to the clip before it.")
                }
                .accessibilityIdentifier("settings-merge-double-copies")
                if model.preferences.mergeDoubleCopies {
                    Toggle("Play a sound", isOn: $model.preferences.playsMergeSound)
                        .accessibilityIdentifier("settings-merge-sound")
                }
            }

            Section {
                Toggle("Show actions after copying", isOn: $model.preferences.copyActions.isEnabled)
                    .accessibilityIdentifier("settings-copy-actions")
                if model.preferences.copyActions.isEnabled {
                    Toggle("Colors", isOn: $model.preferences.copyActions.colors)
                        .accessibilityIdentifier("settings-copy-actions-colors")
                    Toggle("Links", isOn: $model.preferences.copyActions.links)
                        .accessibilityIdentifier("settings-copy-actions-links")
                    Toggle("One-time codes", isOn: $model.preferences.copyActions.oneTimeCodes)
                        .accessibilityIdentifier("settings-copy-actions-codes")
                }
            }

            Section {
                Toggle(isOn: $model.preferences.notchShelf) {
                    Text("Notch shelf")
                    Text(
                        "Drag anything to the notch, or to the top center of a screen without one.")
                }
                .accessibilityIdentifier("settings-notch-shelf")
            }

            Section {
                LabeledContent {
                    Button("Open Intelligence…") { model.intelligenceWindow.show(model: model) }
                        .accessibilityIdentifier("open-intelligence")
                } label: {
                    Text("Intelligence")
                    Text(
                        // swiftlint:disable:next line_length
                        "On-device titles, semantic retrieval, screenshot OCR and secret detection — each a toggle, all local."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }
}

/// The privacy hard rule, stated once in Settings: copies marked concealed,
/// transient or auto-generated are sensed and never read. No switch, because
/// there is nothing to turn off.
private struct ConcealedRuleCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.xs) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Built-in rule · concealed and transient copies")
                    .font(.body.weight(.medium))
                Text(
                    // swiftlint:disable:next line_length
                    "Password managers and some apps mark a copy as concealed, transient or auto-generated. Gancho senses the mark and stops there: the content is never read, stored, indexed or synced. This cannot be turned off."
                )
                .font(.footnote)
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    ForEach(Self.types, id: \.self) { type in
                        Text(verbatim: type)
                            .font(GanchoType.font(.data, size: 10))
                            .foregroundStyle(GanchoTokens.Palette.ink2)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(
                                GanchoTokens.Palette.controlFill,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Image(systemName: "lock")
                .foregroundStyle(GanchoTokens.Palette.ink2)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture-concealed-rule-card")
    }

    /// The marks the monitor vetoes before any read, as their pasteboard names.
    private static let types = [
        SensitivePasteboardTypes.concealed,
        String(SensitivePasteboardTypes.transient.split(separator: ".").last ?? ""),
        String(SensitivePasteboardTypes.autoGenerated.split(separator: ".").last ?? "")
    ]
}
