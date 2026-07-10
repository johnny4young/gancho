import AppKit
import ClipboardCore
import GanchoDesign
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Capture: the editable never-capture app list (MKT-01). The veto
/// itself runs in `MacPasteboardMonitor` BEFORE any pasteboard read; this is
/// only its management surface: excluded apps with real names/icons, built-in
/// exclusions tagged "Default", three no-typing ways to add (running apps,
/// /Applications picker, manual bundle id), and a one-click restore of the
/// built-in exclusions.
struct DenylistSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var newDenylistEntry = ""

    var body: some View {
        Section("Never capture from these apps") {
            ForEach(model.denylistEntries, id: \.self) { bundleID in
                denylistRow(bundleID)
            }
            if model.hasDisabledDenylistSuggestions {
                Button("Restore default exclusions") { model.restoreDenylistDefaults() }
                    .accessibilityIdentifier("denylist-restore-defaults")
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
            Button("Choose from Applications…") { chooseApplicationsToExclude() }
                .accessibilityIdentifier("denylist-choose-app")
            HStack {
                TextField("Bundle identifier", text: $newDenylistEntry)
                    .accessibilityIdentifier("denylist-add-field")
                Button("Add") {
                    guard !newDenylistEntry.isEmpty else { return }
                    model.addToDenylist(newDenylistEntry)
                    newDenylistEntry = ""
                }
                .accessibilityIdentifier("denylist-add-button")
            }
            Text("A bundle identifier looks like com.apple.Safari.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Password managers and banking apps are excluded by default.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// One excluded app: icon + display name when the app is installed (the
    /// raw bundle id stays visible as a caption — it's what the veto matches),
    /// a "Default" tag on the built-in suggestions, and the remove button.
    private func denylistRow(_ bundleID: String) -> some View {
        let info = appInfo(for: bundleID)
        return HStack(spacing: GanchoTokens.Spacing.xs) {
            if let icon = info.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: info.name)
                    .accessibilityIdentifier("denylist-row-\(bundleID)")
                if info.name != bundleID {
                    Text(verbatim: bundleID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if SourceAppDenylist.suggestedBundleIDs.contains(bundleID) {
                Text("Default")
                    .font(.caption2)
                    .padding(.horizontal, GanchoTokens.Spacing.xxs)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                model.removeFromDenylist(bundleID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove"))
            .accessibilityIdentifier("denylist-remove-\(bundleID)")
        }
    }

    private struct DeniedAppInfo {
        let name: String
        let icon: NSImage?
    }

    /// Resolves a bundle id to its installed app's name + icon; an app that
    /// isn't installed (or an iOS-only id from the suggestions) falls back to
    /// the bare bundle id with no icon.
    private func appInfo(for bundleID: String) -> DeniedAppInfo {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return DeniedAppInfo(name: bundleID, icon: nil) }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
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
