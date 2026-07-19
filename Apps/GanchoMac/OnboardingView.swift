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
    @State private var showMigrationImporter = false

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
                Button("Skip") { finish(completed: false, openPanel: false) }
                    .accessibilityIdentifier("onboarding-skip")
                Spacer()
                Button(step < 2 ? "Continue" : "Open Gancho panel") {
                    if step < 2 {
                        step += 1
                    } else {
                        finish(completed: true, openPanel: true)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-continue")
            }
        }
        .padding(GanchoTokens.Spacing.xl)
        .frame(width: 520, height: 420)
        .sheet(isPresented: $showMigrationImporter) {
            MigrationImportView()
        }
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
            HStack(spacing: GanchoTokens.Spacing.sm) {
                Label(
                    "Your first clips get smart AI titles, free and on-device.",
                    systemImage: "sparkles"
                )
                .foregroundStyle(.tint)
                Spacer(minLength: 0)
                Button("Import clipboard history…", systemImage: "arrow.down.doc") {
                    showMigrationImporter = true
                }
                .accessibilityIdentifier("onboarding-open-migration-importer")
            }
            .font(.footnote)
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
                // swiftlint:disable:next line_length
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
                // swiftlint:disable:next line_length
                "Press the shortcut, pick a clip with ↑↓, hit Enter — it pastes right where you were typing. That's the whole loop."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Label(
                "The real panel opens next so you can search and reuse a clip now.",
                systemImage: "arrow.right.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Text("If direct paste is unavailable, Gancho copies the clip so you can press ⌘V.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func finish(completed: Bool, openPanel: Bool) {
        model.finishOnboarding(completed: completed, openPanel: openPanel)
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
