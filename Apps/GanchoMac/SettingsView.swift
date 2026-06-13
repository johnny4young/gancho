import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Native Settings scene, five tabs. Every control binds straight into the
/// model, so changes apply live — no restart, no Apply button.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            CaptureSettingsTab()
                .tabItem { Label("Capture", systemImage: "doc.on.clipboard") }
            RetentionSettingsTab()
                .tabItem { Label("Retention", systemImage: "clock.arrow.circlepath") }
            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            ProSettingsTab()
                .tabItem { Label("Pro", systemImage: "star") }
        }
        .frame(width: 520, height: 380)
        .accessibilityIdentifier("settings")
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var shortcutWarning: String?

    var body: some View {
        @Bindable var model = model
        Form {
            KeyboardShortcuts.Recorder("Panel shortcut:", name: .togglePanel) { shortcut in
                shortcutWarning = shortcut.flatMap {
                    ShortcutConflicts.conflict(with: "\($0)")
                }
            }
            if let shortcutWarning {
                Label {
                    Text("This shortcut is used by the system (\(shortcutWarning)).")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.callout)
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    // SMAppService applies live; revert the toggle on failure.
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            KeyboardShortcuts.Recorder("Cyclic paste shortcut:", name: .cyclicPaste)
            KeyboardShortcuts.Recorder("Paste from stack shortcut:", name: .pasteFromStack)

            Picker("Panel position", selection: positionBinding) {
                Text("Centered").tag(PanelPosition.centered)
                Text("At mouse cursor").tag(PanelPosition.atCursor)
                Text("Last position").tag(PanelPosition.lastPosition)
            }

            Toggle("Show in Dock", isOn: $model.showInDock)

            Section {
                HStack {
                    Button("Export settings…") { exportSettings() }
                    Button("Import settings…") { importSettings() }
                }
                HStack {
                    Button("Back up history…") { backupHistory() }
                    Button("Restore from backup…") { restoreHistory() }
                }
                Text("Backups are portable archives on YOUR disk — never uploaded.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }

    private var positionBinding: Binding<PanelPosition> {
        Binding(
            get: { model.panel.position },
            set: { model.panel.position = $0 })
    }

    private func exportSettings() {
        guard let data = try? model.settingsSnapshot().encoded() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "gancho-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func backupHistory() {
        guard let store = model.grdbStore else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gancho-backup.ganchoarchive"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { try? await GanchoArchive.export(from: store, to: url) }
    }

    private func restoreHistory() {
        guard let store = model.grdbStore else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            _ = try? await GanchoArchive.restore(from: url, into: store)
            await model.refreshRecents()
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
            let data = try? Data(contentsOf: url),
            let snapshot = try? SettingsSnapshot.decode(data)
        else { return }
        model.apply(snapshot)
    }
}

private struct CaptureSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var newDenylistEntry = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Capture images", isOn: $model.preferences.captureImages)
            Toggle("Capture copied files", isOn: $model.preferences.captureFileReferences)
            Toggle("Keep rich text formatting", isOn: $model.preferences.captureRichText)

            Section("Never capture from these apps") {
                ForEach(model.denylistEntries, id: \.self) { bundleID in
                    HStack {
                        Text(verbatim: bundleID)
                        Spacer()
                        Button(role: .destructive) {
                            model.removeFromDenylist(bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel(Text("Remove"))
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $newDenylistEntry)
                        .accessibilityIdentifier("denylist-add-field")
                    Button("Add") {
                        guard !newDenylistEntry.isEmpty else { return }
                        model.addToDenylist(newDenylistEntry)
                        newDenylistEntry = ""
                    }
                }
                Text("Password managers and banking apps are excluded by default.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }
}

private struct RetentionSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Keep history for", selection: $model.retentionPolicy.global) {
                windowOptions
            }
            Picker(
                "Images", selection: perKindBinding(.image)
            ) { windowOptionsWithDefault }
            Picker(
                "Text", selection: perKindBinding(.text)
            ) { windowOptionsWithDefault }

            Picker(
                "Sensitive items expire after",
                selection: $model.retentionPolicy.sensitiveLifetime
            ) {
                Text("5 minutes").tag(TimeInterval(300))
                Text("10 minutes").tag(TimeInterval(600))
                Text("30 minutes").tag(TimeInterval(1800))
            }
            Text("Pinned clips and boards never expire.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }

    @ViewBuilder private var windowOptions: some View {
        Text("24 hours").tag(RetentionPolicy.Window.day)
        Text("7 days").tag(RetentionPolicy.Window.week)
        Text("30 days").tag(RetentionPolicy.Window.month)
        Text("90 days").tag(RetentionPolicy.Window.quarter)
        Text("Forever").tag(RetentionPolicy.Window.never)
    }

    @ViewBuilder private var windowOptionsWithDefault: some View {
        Text("Use global").tag(RetentionPolicy.Window?.none)
        Text("24 hours").tag(RetentionPolicy.Window?.some(.day))
        Text("7 days").tag(RetentionPolicy.Window?.some(.week))
        Text("30 days").tag(RetentionPolicy.Window?.some(.month))
        Text("90 days").tag(RetentionPolicy.Window?.some(.quarter))
    }

    private func perKindBinding(_ kind: ClipContentKind) -> Binding<RetentionPolicy.Window?> {
        Binding(
            get: { model.retentionPolicy.perKind[kind] },
            set: { model.retentionPolicy.perKind[kind] = $0 })
    }
}

private struct PrivacySettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Private mode (pause capture)", isOn: $model.preferences.isPrivateModePaused)
            KeyboardShortcuts.Recorder("Private mode shortcut:", name: .togglePrivateMode)
            Toggle(
                "Pause automatically while sharing the screen",
                isOn: $model.autoPauseOnScreenShare)
            Text(
                "Secrets and card numbers are always masked in previews; revealing them takes an explicit click."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button("Open Privacy Center") {
                model.privacyCenterWindow.show(model: model)
            }
            Button("Save support bundle…") { saveSupportBundle() }
            Text(
                "The support bundle contains versions, settings, and counters — never clipboard content."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Toggle(
                "Share anonymous usage analytics",
                isOn: Binding(
                    get: { !model.telemetryOptedOut },
                    set: { model.telemetryOptedOut = !$0 }))
            Text(
                "Bucketed counts only — never clipboard content. Takes effect on next launch."
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
        guard let store = model.grdbStore else { return }
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
            try? (try? bundle.encoded())?.write(to: url, options: .atomic)
        }
    }
}

private struct ProSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            LabeledContent(
                "Plan",
                value: model.tier == .pro
                    ? String(localized: "Pro") : String(localized: "Free"))
            Button("See what Pro adds") {
                model.paywallWindow.show(trigger: .settingsPro, model: model)
            }
            Text("Pro — iCloud sync, unlimited pins and boards — arrives with launch.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }
}
