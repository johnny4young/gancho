import AppKit
import ClipboardCore
import GanchoAppCore
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
    @State private var overview = PrivacyOverview()

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                PrivacyStatusTiles(overview: overview)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Capture control") {
                Toggle(isOn: $model.preferences.isPrivateModePaused) {
                    Text("Private mode (pause capture)")
                    Text("Nothing is saved while on. Pasting keeps working.")
                }
                ShortcutRecorder("Private mode shortcut:", name: .togglePrivateMode)
                Picker(selection: $model.privateModeAutoOff) {
                    ForEach(PrivateModeAutoOff.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Text("Turn Private mode off after")
                    Text("So a pause never silently becomes a week.")
                }
                .accessibilityIdentifier("private-mode-auto-off-picker")
                Toggle(isOn: $model.autoPauseOnScreenShare) {
                    Text("Pause automatically while sharing the screen")
                    Text("Zoom, Teams and Screen Sharing are detected.")
                }
                footnote("Secrets and card numbers stay masked; revealing one takes a click.")
            }

            Section("Searches and Spotlight") {
                Toggle(isOn: $model.rememberSearches) {
                    Text("Remember searches")
                    Text(
                        "Recall recent panel searches with ⌘↑. Stored only on this Mac; turning this off erases them."
                    )
                }
                Toggle("Show snippets and pins in Spotlight", isOn: $model.spotlightIndexing)
                    .accessibilityIdentifier("spotlight-indexing-toggle")
                footnote(
                    // swiftlint:disable:next line_length
                    "Only snippets and pinned clips reach the system index — never raw history, secrets or expiring clips. Turning this off removes them at once."
                )
                .accessibilityIdentifier("spotlight-indexing-privacy-note")
            }

            Section("Diagnostics") {
                Toggle(
                    isOn: Binding(
                        get: { model.telemetryConsent == .enabled },
                        set: { model.setTelemetryConsent($0 ? .enabled : .disabled) })
                ) {
                    Text("Share anonymous usage diagnostics")
                    Text(
                        "Counts and broad buckets only — never clipboard content, titles, searches or source-app names."
                    )
                }
                .accessibilityIdentifier("telemetry-consent-toggle")
                HStack {
                    Button("Save support bundle…") { saveSupportBundle() }
                    footnote("Versions, settings and counters — never clipboard content.")
                }
                if let supportNote {
                    Text(verbatim: supportNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("support-bundle-note")
                }
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
        .task { overview = await model.privacyOverview() }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
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
