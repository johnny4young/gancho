import ClipboardCore
import CoreSpotlight
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
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
    // Registers the app with APNs at launch (see `GanchoiOSAppDelegate`):
    // CKSyncEngine only auto-fetches remote changes when the process holds a
    // push token, and a fresh install starts without one until it asks.
    @UIApplicationDelegateAdaptor(GanchoiOSAppDelegate.self) private var appDelegate
    @State private var model: IOSAppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let model = IOSAppModel()
        _model = State(initialValue: model)
        // Expose the model's content-free diagnostics log to the app delegate,
        // so a push-registration failure lands in "Recent issues" like macOS.
        GanchoiOSRuntime.model = model
    }
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
            .alert(
                "Help improve Gancho?",
                isPresented: Binding(
                    get: { model.isTelemetryConsentPromptPresented },
                    set: { model.isTelemetryConsentPromptPresented = $0 })
            ) {
                Button("Allow anonymous diagnostics") {
                    model.setTelemetryConsent(.enabled)
                }
                Button("Keep disabled", role: .cancel) {
                    model.setTelemetryConsent(.disabled)
                }
            } message: {
                Text(
                    // swiftlint:disable:next line_length
                    "Gancho can share anonymous feature counts and broad performance buckets. It never sends clipboard content, titles, searches, or source-app names."
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let suggestion = model.reuseSuggestion {
                    ReuseSuggestionBanner(
                        suggestion: suggestion,
                        onAccept: { Task { await model.acceptReuseSuggestion() } },
                        onDismiss: { model.dismissReuseSuggestion() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.reuseSuggestion)
            // Post-launch maintenance: the cosmetic legacy-preview backfill
            // moved off the synchronous store open (it scanned image rows on
            // every cold launch); run it once the first frame is up. The
            // Spotlight reconcile follows: it repairs any curation change the
            // app missed and applies the toggle state.
            .task {
                guard let full = model.full else { return }
                try? await full.backfillLegacyPreviews()
                model.refreshSpotlight()
            }
            // A curated snippet opened from Spotlight lands on its detail via
            // the same deep link the widgets use.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard
                    let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier]
                        as? String,
                    let url = URL(string: "gancho://clip/\(identifier)")
                else { return }
                model.handleDeepLink(url)
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

/// Weak handle to the live model so the UIKit app delegate — which SwiftUI
/// constructs separately from the `@State` model — can reach its content-free
/// diagnostics log. Mirrors macOS's `GanchoRuntime.model`.
@MainActor
enum GanchoiOSRuntime {
    static weak var model: IOSAppModel?
}

/// Registers the app with APNs at launch. CKSyncEngine subscribes to and
/// consumes CloudKit's change pushes itself, but only once the process holds a
/// device token — which a window app requests here (a fresh install has none,
/// so inbound sync goes quiet until it asks). The success callback is a no-op
/// (the app only needs to BE registered, not to forward the payload); the
/// failure callback logs content-free so a lost subscription is diagnosable.
final class GanchoiOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {}

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            GanchoiOSRuntime.model?.diagnostics.record(
                String(localized: "Sync"),
                String(
                    localized:
                        "Couldn’t subscribe to iCloud change notifications; inbound sync may lag."))
        }
    }
}
