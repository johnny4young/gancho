import AppKit
import ClipboardCore
import GanchoDesign
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Capture: the editable never-capture app list. The veto
/// itself runs in `MacPasteboardMonitor` BEFORE any pasteboard read; this is
/// only its management surface. The user's own exclusions lead, one "Add app"
/// menu gathers the three ways to add one (a running app, the /Applications
/// picker, a typed bundle id with live validation), and the twenty built-in
/// exclusions fold into a single row: grouped by category, each with a
/// switch, because turning off a password manager's protection should not
/// look like deleting a row.
struct DenylistSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var newDenylistEntry = ""
    @State private var isAddingByIdentifier = false
    @State private var showsBuiltInExclusions = false
    @FocusState private var identifierFieldFocused: Bool

    var body: some View {
        Section("Never capture from these apps") {
            ForEach(model.userDenylistEntries, id: \.self) { bundleID in
                userRow(bundleID)
            }
            addRow
            if isAddingByIdentifier {
                identifierEntry
            }
            builtInExclusions
            Text(
                "Built-in exclusions switch off one by one; your own entries are removed with the minus."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - User entries

    /// One app the user excluded: icon + display name when installed (the raw
    /// bundle id stays visible as a caption — it's what the veto matches) and
    /// the remove button.
    private func userRow(_ bundleID: String) -> some View {
        let info = appInfo(for: bundleID)
        return HStack(spacing: GanchoTokens.Spacing.xs) {
            appIcon(info.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: info.name)
                    .accessibilityIdentifier(
                        denylistAccessibilityIdentifier("row", bundleID: bundleID))
                if info.name != bundleID {
                    Text(verbatim: bundleID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                model.removeFromDenylist(bundleID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove"))
            .accessibilityIdentifier(denylistAccessibilityIdentifier("remove", bundleID: bundleID))
        }
    }

    // MARK: - Add

    /// The three no-typing-first ways to add an app, behind one control.
    private var addRow: some View {
        HStack {
            Menu {
                Menu("Running app") {
                    ForEach(runningApps) { app in
                        Button {
                            model.addToDenylist(app.id)
                        } label: {
                            Text(verbatim: app.name)
                        }
                    }
                }
                .accessibilityIdentifier("denylist-add-running")
                Button("From Applications…") { chooseApplicationsToExclude() }
                    .accessibilityIdentifier("denylist-choose-app")
                Button("By bundle identifier…") {
                    isAddingByIdentifier = true
                    identifierFieldFocused = true
                }
                .accessibilityIdentifier("denylist-add-by-id")
            } label: {
                Label("Add app", systemImage: "plus")
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityIdentifier("denylist-add-menu")
            Spacer()
        }
    }

    /// The manual path: the field validates as you type, Add stays disabled
    /// until the text has a bundle identifier's shape, and the reason sits
    /// right under the field instead of a silent no-op.
    private var identifierEntry: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                TextField("Bundle identifier", text: $newDenylistEntry)
                    .textFieldStyle(.roundedBorder)
                    .focused($identifierFieldFocused)
                    .onSubmit(addTypedIdentifier)
                    .accessibilityIdentifier("denylist-add-field")
                Button("Add", action: addTypedIdentifier)
                    .disabled(!typedIdentifierIsPlausible)
                    .accessibilityIdentifier("denylist-add-button")
                Button("Cancel") {
                    newDenylistEntry = ""
                    isAddingByIdentifier = false
                }
                .accessibilityIdentifier("denylist-add-cancel")
            }
            if showsIdentifierError {
                Label {
                    Text(
                        "A bundle identifier has at least two dot-separated parts, like com.apple.Safari."
                    )
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .font(.footnote)
                .foregroundStyle(GanchoTokens.Palette.danger)
                .accessibilityIdentifier("denylist-add-error")
            }
        }
    }

    private var typedIdentifierIsPlausible: Bool {
        SourceAppDenylist.isPlausibleBundleIdentifier(newDenylistEntry)
    }

    /// Only once there is something to judge — an empty field is not wrong yet.
    private var showsIdentifierError: Bool {
        !newDenylistEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !typedIdentifierIsPlausible
    }

    private func addTypedIdentifier() {
        guard typedIdentifierIsPlausible else { return }
        model.addToDenylist(newDenylistEntry.trimmingCharacters(in: .whitespacesAndNewlines))
        newDenylistEntry = ""
        isAddingByIdentifier = false
    }

    // MARK: - Built-in exclusions

    private var builtInExclusions: some View {
        DisclosureGroup(isExpanded: $showsBuiltInExclusions) {
            ForEach(SourceAppDenylist.SuggestionCategory.allCases, id: \.self) { category in
                Text(categoryTitle(category))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, GanchoTokens.Spacing.xxs)
                ForEach(SourceAppDenylist.suggestions.filter { $0.category == category }) {
                    suggestionRow($0)
                }
            }
            if model.hasDisabledDenylistSuggestions {
                Button("Restore default exclusions") { model.restoreDenylistDefaults() }
                    .accessibilityIdentifier("denylist-restore-defaults")
            }
        } label: {
            // The whole row toggles, not just the chevron.
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsBuiltInExclusions.toggle() }
            } label: {
                HStack {
                    Text("Built-in exclusions")
                    Spacer()
                    Text(
                        "\(SourceAppDenylist.suggestions.count) · password managers and banking apps"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("denylist-built-in")
        }
    }

    /// A built-in exclusion: installed apps show their real icon and name;
    /// the rest read dimmed with the catalog name, so a wall of raw bundle ids
    /// never returns. The switch is the exclusion state.
    private func suggestionRow(_ suggestion: SourceAppDenylist.Suggestion) -> some View {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: suggestion.id)
        let info = installed.map { appInfo(at: $0, fallback: suggestion.name) }
        return HStack(spacing: GanchoTokens.Spacing.xs) {
            appIcon(info?.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: info?.name ?? suggestion.name)
                    .foregroundStyle(info == nil ? .secondary : .primary)
                HStack(spacing: GanchoTokens.Spacing.xxs) {
                    if info == nil {
                        Text("Not installed")
                        Text(verbatim: "·")
                    }
                    Text(verbatim: suggestion.id)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                isOn: Binding(
                    get: { model.isSuggestedExclusionActive(suggestion.id) },
                    set: { model.setSuggestedExclusion(suggestion.id, active: $0) })
            ) {
                Text(verbatim: suggestion.name)
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier(
                denylistAccessibilityIdentifier("toggle", bundleID: suggestion.id))
        }
    }

    private func categoryTitle(
        _ category: SourceAppDenylist.SuggestionCategory
    ) -> LocalizedStringKey {
        switch category {
        case .passwordManagers: "Password managers"
        case .banking: "Banking"
        }
    }

    // MARK: - Shared pieces

    @ViewBuilder private func appIcon(_ icon: NSImage?) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .foregroundStyle(.quaternary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }

    /// Accessibility selectors stay kebab-case even when the bundle identifier
    /// contains dots or capitals. The visible caption retains the original id.
    private func denylistAccessibilityIdentifier(_ role: String, bundleID: String) -> String {
        let slug = bundleID.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")
        return "denylist-\(role)-\(slug)"
    }

    private struct DeniedAppInfo {
        let name: String
        let icon: NSImage?
    }

    /// Resolves a bundle id to its installed app's name + icon; an app that
    /// isn't installed falls back to the bare bundle id with no icon.
    private func appInfo(for bundleID: String) -> DeniedAppInfo {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return DeniedAppInfo(name: bundleID, icon: nil) }
        return appInfo(at: url, fallback: bundleID)
    }

    private func appInfo(at url: URL, fallback: String) -> DeniedAppInfo {
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        if name.isEmpty { name = fallback }
        return DeniedAppInfo(name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
    }

    /// The no-typing path for apps that aren't running: pick bundles straight
    /// from /Applications.
    private func chooseApplicationsToExclude() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = String(localized: "Choose apps whose copies Gancho should never capture.")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                model.addToDenylist(bundleID)
            }
        }
    }

    private struct RunningApp: Identifiable {
        let id: String  // bundle identifier
        let name: String
    }

    /// Currently-running, Dock-visible apps not already on the denylist — the
    /// no-typing way to add one (you rarely know an app's bundle id by heart).
    private var runningApps: [RunningApp] {
        let denied = Set(model.userDenylistEntries)
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
