import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var model
    let showMigrationImporter: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Local state, like Launch at login: the controller's flag isn't
    /// observable, so a Binding straight into it would leave the switch stale.
    @State private var ambientTint = false
    @State private var translucentBackground = false
    @State private var panelSize: PanelSizePreset?
    @State private var shortcutWarning: String?
    @State private var loginNote: String?
    @State private var transferNote: String?
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue

    var body: some View {
        @Bindable var model = model
        Form {
            ShortcutRecorder("Panel shortcut:", name: .togglePanel) { shortcut in
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

            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { launchAtLogin }, set: { updateLaunchAtLogin($0) })
            )
            .accessibilityIdentifier("launch-at-login-toggle")
            .onAppear { syncLaunchAtLogin() }
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in
                syncLaunchAtLogin()
            }
            if let loginNote {
                Text(verbatim: loginNote)
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("launch-at-login-note")
            }

            ShortcutRecorder("Cyclic paste shortcut:", name: .cyclicPaste)
            ShortcutRecorder("Paste from stack shortcut:", name: .pasteFromStack)
            ShortcutRecorder("Skip in stack shortcut:", name: .pasteStackSkip)
            ShortcutRecorder("Back in stack shortcut:", name: .pasteStackBack)
            ShortcutRecorder("Copy screen text shortcut:", name: .copyScreenText)

            Picker("Panel position", selection: positionBinding) {
                Text("Centered").tag(PanelPosition.centered)
                Text("At mouse cursor").tag(PanelPosition.atCursor)
                Text("Last position").tag(PanelPosition.lastPosition)
            }

            Section("Panel") {
                Picker("Text size", selection: textSizeBinding) {
                    Text("Small").tag(PanelTextSize.small)
                    Text("Standard").tag(PanelTextSize.standard)
                    Text("Large").tag(PanelTextSize.large)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("panel-text-size")

                Picker("Panel size", selection: panelSizeSelection) {
                    Text("Compact").tag(PanelSizePreset?.some(.compact))
                    Text("Standard").tag(PanelSizePreset?.some(.standard))
                    Text("Large").tag(PanelSizePreset?.some(.large))
                }
                .pickerStyle(.segmented)
                .onAppear { panelSize = PanelSizePreset.matching(model.panel.preferredContentSize) }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)
                ) { notification in
                    guard let window = notification.object as? NSWindow,
                        model.panel.isPanelWindow(window)
                    else { return }
                    panelSize = PanelSizePreset.matching(
                        window.contentRect(forFrameRect: window.frame).size)
                }
                .accessibilityIdentifier("panel-size")
                Text("Manual resizing is remembered automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Translucent background", isOn: $translucentBackground)
                    .onAppear { translucentBackground = model.panel.translucentBackground }
                    .onChange(of: translucentBackground) { _, enabled in
                        model.panel.translucentBackground = enabled
                    }
                    .accessibilityIdentifier("panel-translucent-background")
                Toggle("Ambient color", isOn: $ambientTint)
                    .onAppear { ambientTint = model.panel.ambientTint }
                    .onChange(of: ambientTint) { _, enabled in
                        model.panel.ambientTint = enabled
                    }
                    .accessibilityIdentifier("panel-ambient-tint")
                Text("A faint wash of the selected clip’s color behind the list and the peek.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Appearance", selection: $model.appearance) {
                Text("Auto").tag(AppearancePreference.auto)
                Text("Light").tag(AppearancePreference.light)
                Text("Dark").tag(AppearancePreference.dark)
            }
            .pickerStyle(.segmented)

            Picker("Language", selection: $appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.displayName).tag(language.rawValue)
                }
            }

            Section {
                Button("Import clipboard history…", systemImage: "arrow.down.doc") {
                    showMigrationImporter()
                }
                .accessibilityIdentifier("open-migration-importer")
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
                if let transferNote {
                    Text(verbatim: transferNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("backup-transfer-note")
                }
            }

            Section {
                Button("My Clipboard, Wrapped…", systemImage: "gift") { model.exportWrapped() }
                    .accessibilityIdentifier("export-wrapped")
                Text("A shareable stats card — generated on-device, never uploaded.")
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

    /// Only a user write invokes ServiceManagement. Reconciling a failed write
    /// must not trigger the opposite registration action through onChange.
    private func updateLaunchAtLogin(_ enabled: Bool) {
        loginNote = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginNote = String(localized: "Launch at login couldn’t be updated. Try again.")
        }
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if enabled, loginNote == nil, status == .requiresApproval {
            loginNote = String(
                localized:
                    "Allow Gancho in Login Items in System Settings to enable automatic launch.")
        }
    }

    /// Approval happens in System Settings, so an enabled status retires any note.
    private func syncLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if launchAtLogin { loginNote = nil }
    }

    private var textSizeBinding: Binding<PanelTextSize> {
        Binding(
            get: { model.panel.textSize },
            set: { model.panel.textSize = $0 })
    }

    /// Resizes only on a user choice, never when the remembered size is shown.
    private var panelSizeSelection: Binding<PanelSizePreset?> {
        Binding(
            get: { panelSize },
            set: { preset in
                panelSize = preset
                if let preset { model.panel.resize(to: preset) }
            })
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "gancho-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // The user picked a destination, so a failure has to say so — a
        // silently missing file is worse than an error. Same content-free
        // discipline as backup: no path, no payload.
        do {
            try model.settingsSnapshot().encoded().write(to: url, options: .atomic)
            transferNote = String(localized: "Settings exported.")
        } catch {
            transferNote = String(localized: "Those settings couldn’t be exported.")
            model.diagnostics.record(
                String(localized: "Settings"),
                String(localized: "Settings couldn’t be exported."))
        }
    }

    private func backupHistory() {
        guard let store = model.grdbForEngines else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gancho-backup.ganchoarchive"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Detector-flagged secrets never leave the encrypted store via backup:
        // they carry a short expiry precisely so they don't persist, and an
        // archive on disk is permanent plaintext.
        transferNote = nil
        Task {
            do {
                try await GanchoArchive.export(
                    from: store, to: url, options: .init(excludeSensitive: true),
                    replacement: .replaceExisting)
                transferNote = String(localized: "Backup saved.")
            } catch {
                // Same content-free discipline as restore: no paths, no
                // payloads — one actionable note plus a diagnostics entry.
                transferNote = String(localized: "That backup couldn’t be created.")
                model.diagnostics.record(
                    String(localized: "Backup"),
                    String(localized: "A backup couldn’t be created."))
                // The exporter owns and cleans its private stage. The selected
                // destination may be the user's last usable backup.
            }
        }
    }

    private func restoreHistory() {
        guard let store = model.grdbForEngines else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transferNote = nil
        Task {
            do {
                let summary = try await GanchoArchive.restore(from: url, into: store)
                await model.refreshRecents()
                model.notifyStoreChanged(for: .clips)
                transferNote = String(
                    localized:
                        "Restored \(summary.inserted) clips (\(summary.skippedDuplicates) already here)."
                )
            } catch {
                // The selected path and decoder/storage details can contain
                // private filesystem metadata. UI gets one actionable,
                // content-free result; no archive payload is logged.
                transferNote = String(localized: "That backup couldn’t be restored.")
                model.diagnostics.record(
                    String(localized: "Backup"),
                    String(localized: "A backup couldn’t be restored."))
            }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
            let snapshot = try? SettingsSnapshot.decode(data)
        else {
            transferNote = String(localized: "Those settings couldn’t be imported.")
            return
        }
        model.apply(snapshot)
        panelSize = PanelSizePreset.matching(model.panel.preferredContentSize)
        transferNote = String(localized: "Settings imported.")
    }
}
