import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Settings scene, six tabs in the design's pill tab bar. Every control binds
/// straight into the model, so changes apply live — no restart, no Apply button.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $tab)
                .padding(.horizontal, GanchoTokens.Spacing.md)
                .padding(.top, GanchoTokens.Spacing.sm)
                .padding(.bottom, GanchoTokens.Spacing.xs)
            Divider()
            selectedTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 400)
        .accessibilityIdentifier("settings")
    }

    @ViewBuilder private var selectedTab: some View {
        switch tab {
        case .general: GeneralSettingsTab()
        case .capture: CaptureSettingsTab()
        case .retention: RetentionSettingsTab()
        case .privacy: PrivacySettingsTab()
        case .integrations: IntegrationsSettingsTab()
        case .pro: ProSettingsTab()
        case .about: AboutSettingsTab()
        }
    }
}

/// The About screen: a centered app hero, a details card (version, author,
/// license), and the project links — with a manual update check on the
/// direct-download build. Scrolls so nothing is clipped in the short window.
private struct AboutSettingsTab: View {
    @Environment(AppModel.self) private var model

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GanchoTokens.Spacing.lg) {
                hero
                detailsCard
                links
                #if GANCHO_DIRECT_DOWNLOAD
                    Button("Check for Updates…") { model.updater.checkForUpdates() }
                        .buttonStyle(.bordered)
                #endif
            }
            .padding(GanchoTokens.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("settings-about")
    }

    private var hero: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(verbatim: "Gancho").font(.title2.bold())
            Text("Your clipboard, private by design.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow("Version", versionLine, id: "about-version")
            Divider()
            detailRow("Author", "Johnny IV Young Ospino")
            Divider()
            detailRow("License", "MIT")
        }
        .ganchoSurface(radius: GanchoTokens.Radius.md)
    }

    private func detailRow(
        _ label: LocalizedStringKey, _ value: String, id: String? = nil
    ) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: GanchoTokens.Spacing.md)
            let valueText = Text(value).textSelection(.enabled)
            // Only set an identifier when one is given — a blank id is a
            // meaningless, collision-prone query target for UI tests.
            if let id {
                valueText.accessibilityIdentifier(id)
            } else {
                valueText
            }
        }
        .font(.callout)
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.vertical, GanchoTokens.Spacing.sm)
    }

    private var links: some View {
        VStack(spacing: GanchoTokens.Spacing.xxs) {
            aboutLink("Website", systemImage: "safari", url: "https://gancho.app")
            aboutLink(
                "Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right",
                url: "https://github.com/johnny4young/gancho")
            aboutLink(
                "Report an issue", systemImage: "exclamationmark.bubble",
                url: "https://github.com/johnny4young/gancho/issues")
        }
    }

    private func aboutLink(
        _ title: LocalizedStringKey, systemImage: String, url: String
    ) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: GanchoTokens.Spacing.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(GanchoTokens.Palette.accent)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.horizontal, GanchoTokens.Spacing.md)
            .padding(.vertical, GanchoTokens.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ganchoSurface(radius: GanchoTokens.Radius.sm)
    }
}

/// The Settings tabs. Rendered as the design's `TabBar`: plain-text tabs with
/// thin dividers, the active one a solid accent pill (accent follows the OS
/// accent — brand green by default), the rest quiet gray.
private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, capture, retention, privacy, integrations, pro, about

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .capture: "Capture"
        case .retention: "Retention"
        case .privacy: "Privacy"
        case .integrations: "Integrations"
        case .pro: "Pro"
        case .about: "About"
        }
    }
}

private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        // Horizontal scroll so every tab keeps its FULL label (with seven tabs
        // the fixed-width bar squeezed them to "Ge…", "Cap…", …). The selected
        // tab scrolls into view so a hidden one is never silently omitted.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element.id) {
                        index, tab in
                        if index > 0 {
                            Divider().frame(height: 14)
                        }
                        tabButton(tab).id(tab)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
            .onChange(of: selection) { _, new in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isActive = tab == selection
        return Button {
            selection = tab
        } label: {
            Text(tab.titleKey)
                .font(.callout.weight(isActive ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, GanchoTokens.Spacing.sm)
                .padding(.vertical, GanchoTokens.Spacing.xxs)
                .foregroundStyle(isActive ? Color.white : Color.secondary)
                .background(
                    isActive ? GanchoTokens.Palette.accent : Color.clear, in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-tab-\(tab.rawValue)")
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var shortcutWarning: String?
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue

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

    private func exportSettings() {
        guard let data = try? model.settingsSnapshot().encoded() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "gancho-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func backupHistory() {
        guard let store = model.grdbForEngines else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gancho-backup.ganchoarchive"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Detector-flagged secrets never leave the encrypted store via backup:
        // they carry a short expiry precisely so they don't persist, and an
        // archive on disk is permanent plaintext.
        Task {
            try? await GanchoArchive.export(
                from: store, to: url, options: .init(excludeSensitive: true))
        }
    }

    private func restoreHistory() {
        guard let store = model.grdbForEngines else { return }
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

            Section("Intelligence") {
                Button("Open Intelligence…") { model.intelligenceWindow.show(model: model) }
                    .accessibilityIdentifier("open-intelligence")
                Text(
                    // swiftlint:disable:next line_length
                    "On-device titles, semantic search, screenshot OCR, and secret detection — each a toggle, all local."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

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
                Menu("Add a running app…") {
                    ForEach(runningApps) { app in
                        Button {
                            model.addToDenylist(app.id)
                        } label: {
                            Text(verbatim: app.name)
                        }
                    }
                }
                .accessibilityIdentifier("denylist-running-apps")
                HStack {
                    TextField("Bundle identifier", text: $newDenylistEntry)
                        .accessibilityIdentifier("denylist-add-field")
                    Button("Add") {
                        guard !newDenylistEntry.isEmpty else { return }
                        model.addToDenylist(newDenylistEntry)
                        newDenylistEntry = ""
                    }
                }
                Text("A bundle identifier looks like com.apple.Safari.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Password managers and banking apps are excluded by default.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }

    private struct RunningApp: Identifiable {
        let id: String  // bundle identifier
        let name: String
    }

    /// Currently-running, Dock-visible apps not already on the denylist — the
    /// no-typing way to add one (you rarely know an app's bundle id by heart).
    private var runningApps: [RunningApp] {
        let denied = Set(model.denylistEntries)
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, let name = app.localizedName,
                    !denied.contains(id), seen.insert(id).inserted
                else { return nil }
                return RunningApp(id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct RetentionSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("History") {
                Picker("Keep history for", selection: $model.retentionPolicy.global) {
                    windowOptions
                }
                Picker(
                    "Images", selection: perKindBinding(.image)
                ) { windowOptionsWithDefault }
                Picker(
                    "Text", selection: perKindBinding(.text)
                ) { windowOptionsWithDefault }
                Text(
                    // swiftlint:disable:next line_length
                    "A per-type limit overrides the global window; leave a type on Use global to follow it. Pinned clips and boards never expire."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Sensitive items") {
                Picker(
                    "Sensitive items expire after",
                    selection: $model.retentionPolicy.sensitiveLifetime
                ) {
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("10 minutes").tag(TimeInterval(600))
                    Text("30 minutes").tag(TimeInterval(1800))
                }
                Label(
                    // swiftlint:disable:next line_length
                    "Detected secrets — passwords, keys, cards — always follow this limit, even when your history keeps everything longer. It's a safety guard you can shorten but not extend.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
    }

    @ViewBuilder private var windowOptions: some View {
        Text("24 hours").tag(RetentionPolicy.Window.day)
        Text("7 days").tag(RetentionPolicy.Window.week)
        Text("30 days").tag(RetentionPolicy.Window.month)
        Text("90 days").tag(RetentionPolicy.Window.quarter)
        Text("6 months").tag(RetentionPolicy.Window.halfYear)
        Text("1 year").tag(RetentionPolicy.Window.year)
        Text("Forever").tag(RetentionPolicy.Window.never)
    }

    @ViewBuilder private var windowOptionsWithDefault: some View {
        Text("Use global").tag(RetentionPolicy.Window?.none)
        Text("24 hours").tag(RetentionPolicy.Window?.some(.day))
        Text("7 days").tag(RetentionPolicy.Window?.some(.week))
        Text("30 days").tag(RetentionPolicy.Window?.some(.month))
        Text("90 days").tag(RetentionPolicy.Window?.some(.quarter))
        Text("6 months").tag(RetentionPolicy.Window?.some(.halfYear))
        Text("1 year").tag(RetentionPolicy.Window?.some(.year))
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
            Toggle("Remember searches", isOn: $model.rememberSearches)
            Text(
                "Recall recent panel searches with ⌘↑. Stored only on this Mac; turning this off erases them."
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
            try? (try? bundle.encoded())?.write(to: url, options: .atomic)
        }
    }
}

private struct IntegrationsSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Local MCP server") {
                Toggle(
                    "Allow local AI agents (MCP)",
                    isOn: Binding(
                        get: { model.mcpConfig.isEnabled },
                        set: { model.setMCPEnabled($0) }))
                Picker(
                    "Access scope",
                    selection: Binding(
                        get: { model.mcpConfig.scope },
                        set: { model.setMCPScope($0) })
                ) {
                    Text("Metadata only").tag(MCPAccessScope.metadata)
                    Text("Marked boards only").tag(MCPAccessScope.boards)
                    Text("Everything").tag(MCPAccessScope.all)
                }
                .disabled(!model.mcpConfig.isEnabled)
                Text(
                    // swiftlint:disable:next line_length
                    "Lets local AI agents (Claude, Cursor) read your clipboard over a local connection — no network. Off by default."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                if model.mcpConfig.isEnabled {
                    Text("Scope changes apply the next time the gancho mcp server starts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Open MCP Access…") { model.mcpAccessWindow.show(model: model) }
                    .accessibilityIdentifier("open-mcp-access")
                Text(
                    // swiftlint:disable:next line_length
                    "The exposed tools, the metadata-only access log, and the sensitive-veto guarantee live in MCP Access."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if model.mcpConfig.isEnabled {
                Section("Connect an agent") {
                    Text(
                        // swiftlint:disable:next line_length
                        "Turning this on only allows access — your agent runs the server. Install the gancho CLI, then point your agent at it:"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Text(verbatim: "brew install johnny4young/tap/gancho")
                        .font(.footnote.monospaced()).textSelection(.enabled)
                    Text(verbatim: "claude mcp add gancho -- gancho mcp")
                        .font(.footnote.monospaced()).textSelection(.enabled)
                    Button("Copy connect command") {
                        SystemPasteboardWriter().write(
                            .text("claude mcp add gancho -- gancho mcp"), asPlainText: true)
                        model.toasts.show(GanchoToast(message: "Copied"))
                    }
                    .accessibilityIdentifier("copy-mcp-connect")
                }
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
        .accessibilityIdentifier("settings-integrations")
    }
}

private struct ProSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var clipCount: Int?

    var body: some View {
        Form {
            LabeledContent(
                "Plan",
                value: model.tier == .pro
                    ? String(localized: "Pro") : String(localized: "Free"))
            if let clipCount {
                LabeledContent("Clips kept for you", value: clipCount.formatted())
            }
            Button("See what Pro adds") {
                model.paywallWindow.show(trigger: .settingsPro, model: model)
            }
            Text(
                "Pro unlocks unlimited history, pins, boards, and encrypted iCloud sync across your devices."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            #if GANCHO_DIRECT_DOWNLOAD
                Section("Software Updates") {
                    Button("Check for Updates…") { model.updater.checkForUpdates() }
                    Text(
                        "Direct downloads update themselves automatically; you can also check now."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            #endif
            #if DEBUG
                Section {
                    Button {
                        model.resetSyncAndRepull()
                    } label: {
                        Text(verbatim: "Reset & re-pull sync")
                    }
                    .accessibilityIdentifier("debug-reset-sync")
                } header: {
                    Text(verbatim: "Debug")
                }
            #endif
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
        .task {
            // "Kept for you" = everything on disk: the visible clips PLUS the
            // archived ones free-tier enforcement hides but never deletes (the
            // upgrade carrot). Pro releases all archives, so there the archived
            // term is 0 and this equals the visible count.
            guard let store = model.grdbStore, let visible = try? await store.count() else {
                return
            }
            let archived = (try? await store.archivedCount()) ?? 0
            clipCount = visible + archived
        }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environment(model).ganchoTinted())
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "Settings")
            created.styleMask = [.titled, .closable]
            // The tab strip labels the window; a visible "Settings" title only
            // crowded it against the title bar.
            created.titleVisibility = .hidden
            created.isReleasedWhenClosed = false
            created.collectionBehavior = [.moveToActiveSpace]
            created.center()
            window = created
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
}
