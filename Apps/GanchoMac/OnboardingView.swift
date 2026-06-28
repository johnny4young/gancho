import AppKit
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

/// Three-screen welcome: privacy promise up
/// top, teach the core loop, configure the hotkey. Shown once
/// (`hasSeenWelcome`), skippable, reopenable from the menu.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var accessibilityGranted = AXIsProcessTrusted()

    private let accessibilityCheck = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.lg) {
            switch step {
            case 0: valueStep
            case 1: permissionStep
            default: shortcutStep
            }

            HStack {
                Button("Skip") { finish() }
                    .accessibilityIdentifier("onboarding-skip")
                Spacer()
                Button(step < 2 ? "Continue" : "Start using Gancho") {
                    if step < 2 { step += 1 } else { finish() }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-continue")
            }
        }
        .padding(GanchoTokens.Spacing.xl)
        .frame(width: 520, height: 420)
        .accessibilityIdentifier("onboarding")
    }

    /// Screen 1 — value, demonstrated LIVE: the monitor is already running,
    /// so "copy something" genuinely makes it appear right here.
    private var valueStep: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Image(systemName: "paperclip")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Everything you copy, safe and searchable")
                .font(.title2.bold())
            Text("Try it now: copy any text — it appears below instantly.")
                .foregroundStyle(.secondary)

            VStack(spacing: GanchoTokens.Spacing.xxs) {
                ForEach(model.recentItems.prefix(3)) { item in
                    ClipCard(item: item)
                }
                if model.recentItems.isEmpty {
                    Text("Copy something — it will appear here.")
                        .foregroundStyle(.tertiary)
                        .padding(GanchoTokens.Spacing.md)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .top)
            .ganchoSurface()
            Text("Your clips never leave this Mac unless YOU turn on iCloud sync.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Screen 2 — Accessibility, honestly explained, with the deep link and
    /// a live status check (no restart needed once granted).
    private var permissionStep: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Image(systemName: accessibilityGranted ? "checkmark.seal.fill" : "hand.raised")
                .font(.system(size: 44))
                .foregroundStyle(
                    accessibilityGranted
                        ? GanchoTokens.Palette.success : GanchoTokens.Palette.warning)
            Text("One permission for instant pasting")
                .font(.title2.bold())
            Text(
                "To paste a clip directly into the app you're using, macOS requires the Accessibility permission. Gancho uses it ONLY to send the paste keystroke — never to read your screen."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if accessibilityGranted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(GanchoTokens.Palette.success)
            } else {
                ActionButton(
                    "Open System Settings", systemImage: "gear",
                    identifier: "open-accessibility-settings"
                ) {
                    NSWorkspace.shared.open(
                        URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        )!)
                }
                Text("Without it, Gancho still works: clips are copied and you paste with ⌘V.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(accessibilityCheck) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    /// Screen 3 — the global shortcut + guided first paste.
    private var shortcutStep: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Image(systemName: "keyboard")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Your clipboard, one shortcut away")
                .font(.title2.bold())
            KeyboardShortcuts.Recorder("Panel shortcut:", name: .togglePanel)
            Text(
                "Press the shortcut, pick a clip with ↑↓, hit Enter — it pastes right where you were typing. That's the whole loop."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Label(
                "Forgot the shortcut? Gancho also lives in your menu bar — click its icon anytime.",
                systemImage: "menubar.rectangle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Toggle(
                "Also show Gancho in the Dock",
                isOn: Binding(get: { model.showInDock }, set: { model.showInDock = $0 })
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier("onboarding-show-in-dock")
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "has-seen-welcome")
        // Local activation metric: onboarding completion timestamp; the
        // first paste-back timestamp pairs with it (privacy-first telemetry
        // ships the BUCKETS later, never the events' content).
        if UserDefaults.standard.object(forKey: "onboarding-completed-at") == nil {
            UserDefaults.standard.set(
                Date().timeIntervalSince1970, forKey: "onboarding-completed-at")
        }
        model.welcomeWindow.close()
    }
}

/// AppKit window host (the app has no WindowGroup — it's a menu-bar agent).
@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: OnboardingView().environment(model).ganchoTinted())
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "Welcome to Gancho")
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.orderOut(nil)
    }
}
