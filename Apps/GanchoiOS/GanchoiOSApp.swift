import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoSync
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// iOS companion shell (pre-alpha). Proves the honest capture story end to
/// end: intent-based reads only (capture button, UIPasteControl, share
/// extension inbox), detect-before-read hints, and NO background polling —
/// the App Review notes promise exactly this behavior.
@main
struct GanchoiOSApp: App {
    @State private var model = IOSAppModel()
    @Environment(\.scenePhase) private var scenePhase
    /// One-time welcome: iOS's intent-based capture is novel, so first launch
    /// explains the save paths before dropping the user on an empty list.
    @AppStorage("ios-has-seen-welcome") private var hasSeenWelcome = false

    /// UI-test hook: route straight to the Privacy Center on launch (no
    /// welcome, no navigation) so XCUITest can assert the diagnostics log.
    private var routeToPrivacyCenter: Bool {
        ProcessInfo.processInfo.arguments.contains("-open-privacy-center-on-launch")
    }

    /// UI-test hook: land directly on the capture UI without mutating the user's
    /// first-run flag. Capture-flow tests should not depend on simulator defaults.
    private var skipWelcomeOnLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-skip-welcome-on-launch")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if routeToPrivacyCenter {
                    NavigationStack { IOSPrivacyCenterView() }
                } else if UIDevice.current.userInterfaceIdiom == .pad {
                    // iPad gets the sidebar layout; iPhone keeps the stack.
                    IPadSplitView()
                } else {
                    CaptureView()
                }
            }
            .environment(model)
            // Post-launch maintenance: the cosmetic legacy-preview backfill
            // moved off the synchronous store open (it scanned image rows on
            // every cold launch); run it once the first frame is up.
            .task {
                guard let full = model.full else { return }
                try? await full.backfillLegacyPreviews()
            }
            // Widget deep links (`gancho://clip/<id>`) open the right clip.
            .onOpenURL { model.handleDeepLink($0) }
            // Brand-green accent (iOS has no per-app OS accent picker, so green
            // is the default); the Synced check and success states use it too.
            .ganchoTinted()
            .sheet(
                isPresented: Binding(
                    get: { !hasSeenWelcome && !routeToPrivacyCenter && !skipWelcomeOnLaunch },
                    set: { showing in if !showing { hasSeenWelcome = true } })
            ) {
                IOSOnboardingView { hasSeenWelcome = true }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Release the encrypted store's SQLite locks before iOS suspends the
            // process (avoids 0xDEAD10CC), and resume on return to foreground.
            switch phase {
            case .background: DatabaseSuspension.suspend()
            case .active:
                DatabaseSuspension.resume()
                // With the store resumed, run the retention/tier pass the Mac
                // does on a timer — iOS gets it on return to foreground,
                // throttled inside runMaintenance() so frequent app switches
                // don't repeat the full purge + blob sweep.
                Task { await model.runMaintenance() }
            default: break
            }
        }
    }
}
