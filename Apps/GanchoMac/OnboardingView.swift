import AppKit
import Combine
import GanchoAppCore
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

/// Four-step welcome: the privacy promise, the one permission, the global
/// shortcuts, then a live first copy that ends inside the real panel. Shown
/// once (`has-seen-welcome`), skippable, reopenable from the menu.
struct OnboardingView: View {
    @Environment(AppModel.self) var model
    @State var step = Self.initialStep
    @State var accessibilityGranted = Self.isAccessibilityTrusted()
    @State var showMigrationImporter = false
    @State var panelShortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)

    private let accessibilityCheck = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                switch step {
                case .promise: promiseStep
                case .permission: permissionStep
                case .shortcuts: OnboardingShortcutsStep()
                case .firstCopy: firstCopyStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            footer
        }
        .padding(.top, 36)
        .padding(.horizontal, 26)
        .padding(.bottom, 20)
        // The window fixes the height; the steps draw under its transparent title bar.
        .frame(width: 520)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { pageDots.padding(.top, 14).padding(.trailing, 16) }
        .ignoresSafeArea()
        .sheet(isPresented: $showMigrationImporter) {
            MigrationImportView()
        }
        .onReceive(accessibilityCheck) { _ in
            accessibilityGranted = Self.isAccessibilityTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) {
            _ in
            panelShortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)
        }
    }

    private var footer: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            if step.leadingAction == .advance {
                Button("Skip for now") { perform(.advance) }
                    .accessibilityIdentifier("onboarding-skip-for-now")
            } else {
                Button("Skip") { perform(.close) }
                    .accessibilityIdentifier("onboarding-skip")
            }
            Spacer()
            if let previous = step.previous {
                Button("Back") { step = previous }
                    .accessibilityIdentifier("onboarding-back")
            }
            let action = step.primaryAction(accessibilityGranted: accessibilityGranted)
            Button {
                perform(action)
            } label: {
                primaryLabel(action)
            }
            .keyboardShortcut(.defaultAction)
            .ganchoButtonStyle(.primary)
            .accessibilityIdentifier(
                action == .openAccessibilitySettings
                    ? "open-accessibility-settings" : "onboarding-continue")
        }
    }

    private func primaryLabel(_ action: OnboardingAction) -> Text {
        switch action {
        case .openAccessibilitySettings: Text("Open System Settings")
        case .openPanel:
            if let panelShortcut {
                Text("Open Gancho panel \(panelShortcut.description)")
            } else {
                Text("Open Gancho panel")
            }
        case .advance, .close: Text("Continue")
        }
    }

    private func perform(_ action: OnboardingAction) {
        switch action {
        case .advance:
            if let next = step.next { step = next }
        case .close:
            model.finishOnboarding(completed: false, openPanel: false)
        case .openAccessibilitySettings:
            NSWorkspace.shared.open(
                URL(
                    string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )!)
        case .openPanel:
            model.finishOnboarding(completed: true, openPanel: true)
        }
    }

    private var pageDots: some View {
        let count = OnboardingStep.allCases.count
        return HStack(spacing: 4) {
            ForEach(OnboardingStep.allCases, id: \.self) { dot in
                Circle()
                    .fill(dot == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step.rawValue + 1) of \(count)"))
        .accessibilityIdentifier("onboarding-page-dots")
    }

    private static var initialStep: OnboardingStep {
        #if DEBUG
            // Snapshots open each step directly.
            if let index = CommandLine.arguments.firstIndex(of: "-ui-test-onboarding-step"),
                CommandLine.arguments.indices.contains(index + 1),
                let raw = Int(CommandLine.arguments[index + 1]),
                let step = OnboardingStep(rawValue: raw)
            {
                return step
            }
        #endif
        return .promise
    }

    private static func isAccessibilityTrusted() -> Bool {
        #if DEBUG
            // Pins the permission step's state, whatever this Mac has granted.
            if let index = CommandLine.arguments.firstIndex(of: "-ui-test-accessibility-trusted"),
                CommandLine.arguments.indices.contains(index + 1)
            {
                return CommandLine.arguments[index + 1] == "YES"
            }
        #endif
        return AXIsProcessTrusted()
    }
}

/// The heading every step shares: an icon, a title and a short body.
struct OnboardingStepHeader<Icon: View>: View {
    let title: LocalizedStringKey
    let message: Text
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            icon.accessibilityHidden(true)
            Text(title)
                .font(.system(size: 19, weight: .heavy))
                .tracking(-0.19)
                .accessibilityAddTraits(.isHeader)
            message
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            hosting.sizingOptions = []
            let created = NSWindow(contentViewController: hosting)
            // Kept for the window menu and accessibility; the steps carry their own titles.
            created.title = String(localized: "Welcome to Gancho")
            created.styleMask = [.titled, .closable, .fullSizeContentView]
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.isReleasedWhenClosed = false
            created.setContentSize(NSSize(width: 520, height: 420))
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
