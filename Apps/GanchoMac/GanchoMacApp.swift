import ClipboardCore
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

/// Menu-bar agent. The panel (⇧⌘V) is the primary surface; the menu is the
/// secondary, glanceable one. Known MenuBarExtra limitation, documented:
/// SwiftUI gives one click behavior — the menu opens on any click, and the
/// panel opens via its menu item or the global shortcut.
@main
struct GanchoMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra {
            MenuContent()
                .environment(model)
        } label: {
            // Glanceable global state: capturing / paused / private mode.
            Image(systemName: statusSymbol)
                .accessibilityLabel(Text(statusLabel))
        }
    }

    private var statusSymbol: String {
        switch model.monitorStatus {
        case .running: "paperclip"
        case .pausedByUser: "eye.slash"
        case .pausedByScreenShare: "video.slash"
        case .stopped, .pausedByScreenLock: "pause.circle"
        case .deniedByPrivacySettings: "exclamationmark.triangle"
        }
    }

    private var statusLabel: LocalizedStringKey {
        switch model.monitorStatus {
        case .running: "Gancho: capturing"
        case .pausedByUser: "Gancho: private mode"
        case .pausedByScreenShare: "Gancho: paused while sharing"
        case .stopped, .pausedByScreenLock: "Gancho: paused"
        case .deniedByPrivacySettings: "Gancho: pasteboard access denied"
        }
    }
}

struct MenuContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Last five clips — click pastes into the frontmost app.
        if model.recentItems.isEmpty {
            Text("Copy something — it will appear here.")
        } else {
            ForEach(model.recentItems.prefix(5)) { item in
                Button {
                    model.paste(item)
                } label: {
                    Label(
                        title: { Text(item.preview).lineLimit(1) },
                        icon: { Image(systemName: item.kind.symbolName) })
                }
            }
        }

        Divider()

        Button("Open panel") {
            model.panel.show(model: model)
        }
        .keyboardShortcut("v", modifiers: [.shift, .command])

        Button(model.monitorStatus == .running ? "Pause capture" : "Resume capture") {
            model.togglePause()
        }
        Toggle(
            "Private mode",
            isOn: Binding(
                get: { model.preferences.isPrivateModePaused },
                set: { _ in model.togglePrivateMode() }))
        Button("Ignore next copy") {
            model.ignoreNextCopy()
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        Button("Welcome to Gancho") {
            model.welcomeWindow.show(model: model)
        }
        Button("Privacy Center") {
            model.privacyCenterWindow.show(model: model)
        }
        if model.monitorStatus == .deniedByPrivacySettings {
            Button("Fix clipboard access…") {
                model.permissionWindow.show(model: model)
            }
        }
        Toggle(
            "Show in Dock",
            isOn: Binding(get: { model.showInDock }, set: { model.showInDock = $0 }))

        Divider()

        Button("Quit Gancho") {
            NSApplication.shared.terminate(nil)
        }
    }
}
