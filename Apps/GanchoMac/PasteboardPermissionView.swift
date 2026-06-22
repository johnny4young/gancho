import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The pasteboard-permission walkthrough (macOS 27 enforcement readiness,
/// built from the privacy spike's verified matrix). Permission framed as
/// TRUST: Gancho shows exactly when it reads — the Privacy Center proves it.
///
/// Spike corrections baked in: a working deep link DOES exist
/// (`Privacy_Pasteboard`, verified live on 26.5), and permission changes
/// require relaunching the app ("Quit & Reopen") — the copy says so.
struct PasteboardPermissionView: View {
    @Environment(AppModel.self) private var model
    @State private var verdict: PasteboardAccessVerdict = .allowed

    private let recheck = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            switch verdict {
            case .allowed:
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44)).foregroundStyle(GanchoTokens.Palette.success)
                Text("Clipboard access is active")
                    .font(.title2.bold())
                Text(
                    "Gancho can capture your copies. You can audit every read in the Privacy Center."
                )
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .ask:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 44)).foregroundStyle(GanchoTokens.Palette.warning)
                Text("macOS will ask before Gancho reads")
                    .font(.title2.bold())
                Text(
                    "Your Mac is set to confirm clipboard reads. To capture automatically, allow Gancho in System Settings → Privacy & Security → Paste from Other Apps, then relaunch Gancho (macOS applies the change on relaunch)."
                )
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                settingsButton
            case .denied:
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 44)).foregroundStyle(GanchoTokens.Palette.danger)
                Text("Clipboard access is off")
                    .font(.title2.bold())
                Text(
                    "Gancho still works in manual mode: your history stays searchable and you can capture via the share sheet on iPhone. To re-enable automatic capture, allow Gancho in System Settings and relaunch."
                )
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                settingsButton
            }

            Text("Why a permission? So you can see exactly when we read your clipboard.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ActionButton(
                "Open Privacy Center", systemImage: "lock.shield",
                identifier: "permission-privacy-center"
            ) {
                model.privacyCenterWindow.show(model: model)
            }
        }
        .padding(GanchoTokens.Spacing.xl)
        .frame(width: 480)
        .accessibilityIdentifier("pasteboard-permission")
        .onAppear { verdict = SystemPasteboardAccessPolicy().currentVerdict() }
        .onReceive(recheck) { _ in
            verdict = SystemPasteboardAccessPolicy().currentVerdict()
            model.monitor.recheckAccess()
        }
    }

    private var settingsButton: some View {
        ActionButton(
            "Open System Settings", systemImage: "gear",
            identifier: "open-pasteboard-settings"
        ) {
            // Deep link VERIFIED live by the privacy spike on macOS 26.5.
            NSWorkspace.shared.open(
                URL(
                    string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard"
                )!)
        }
    }
}

@MainActor
final class PasteboardPermissionWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: PasteboardPermissionView().environment(model).ganchoTinted())
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "Clipboard Access")
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
