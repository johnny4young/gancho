import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension PrivateModeAutoOff {
    var title: LocalizedStringKey {
        switch self {
        case .fifteenMinutes: "15 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .never: "Until I turn it off"
        }
    }
}

struct PrivacySettingsTab: View {
    @Environment(AppModel.self) private var model
    /// Outcome of the last support-bundle save. Content-free by construction:
    /// it says whether a file was written, never what went into it.
    @State private var supportNote: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Private mode (pause capture)", isOn: $model.preferences.isPrivateModePaused)
            Picker("Turn Private mode off after", selection: $model.privateModeAutoOff) {
                ForEach(PrivateModeAutoOff.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .accessibilityIdentifier("private-mode-auto-off-picker")
            ShortcutRecorder("Private mode shortcut:", name: .togglePrivateMode)
            Toggle(
                "Pause automatically while sharing the screen",
                isOn: $model.autoPauseOnScreenShare)
            Text(
                "Secrets and card numbers are always masked in previews; revealing them takes an explicit click."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Toggle("Remember searches", isOn: $model.rememberSearches)
            Text(
                "Recall recent panel searches with ⌘↑. Stored only on this Mac; turning this off erases them."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Toggle("Show snippets and pins in Spotlight", isOn: $model.spotlightIndexing)
                .accessibilityIdentifier("spotlight-indexing-toggle")
            Text(
                """
                Only snippets and pinned clips reach the system index — never your raw \
                history, secrets, or expiring clips. Turning this off removes them from \
                Spotlight immediately.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("spotlight-indexing-privacy-note")
            Button("Open Privacy Center") {
                model.privacyCenterWindow.show(model: model)
            }
            Button("Save support bundle…") { saveSupportBundle() }
            if let supportNote {
                Text(verbatim: supportNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("support-bundle-note")
            }
            Text(
                "The support bundle contains versions, settings, and counters — never clipboard content."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Toggle(
                "Share anonymous usage diagnostics",
                isOn: Binding(
                    get: { model.telemetryConsent == .enabled },
                    set: { model.setTelemetryConsent($0 ? .enabled : .disabled) })
            )
            .accessibilityIdentifier("telemetry-consent-toggle")
            Text(
                // swiftlint:disable:next line_length
                "Optional anonymous counts and broad performance buckets only — never clipboard content, titles, searches, or source-app names. Off until you allow it; changes apply immediately."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }
}

extension PrivacySettingsTab {
    fileprivate func saveSupportBundle() {
        guard let store = model.grdbForEngines else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gancho-support.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let stats =
                (try? await SupportBundle.gatherStatistics(from: store))
                ?? SupportBundle.Statistics()
            let bundle = SupportBundle(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                    as? String ?? "dev",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                settings: (try? model.settingsSnapshot())
                    ?? SettingsSnapshot(
                        retention: RetentionPolicy(), capturePreferencesJSON: Data()),
                statistics: stats,
                telemetryCounts: [:])
            // This is the path a user reaches BECAUSE something already went
            // wrong. Failing it silently leaves them with nothing to send and
            // no idea why.
            do {
                try bundle.encoded().write(to: url, options: .atomic)
                supportNote = String(localized: "Support bundle saved.")
            } catch {
                supportNote = String(localized: "That support bundle couldn’t be saved.")
                model.diagnostics.record(
                    String(localized: "Support"),
                    String(localized: "A support bundle couldn’t be saved."))
            }
        }
    }
}
