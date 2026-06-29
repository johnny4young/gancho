import AppKit
import GanchoDesign
import GanchoKit
import SwiftUI

/// The contextual paywall: only ever AFTER the first successful paste-back
/// (gatekeeper rule), never as a gateway. No dark patterns — "Stay free"
/// is always visible and free really is forever.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    let trigger: PaywallGatekeeper.Trigger
    @Environment(\.dismiss) private var dismiss

    private let copy = PaywallCopy.standard
    @State private var licenseKey = ""
    @State private var licenseError: String?
    /// Flips to the in-window "Welcome to Pro" celebration on a successful
    /// activation, instead of dismissing in silence — the success moment.
    @State private var didActivate = false

    var body: some View {
        Group {
            if didActivate {
                welcomeToPro
            } else {
                paywallBody
            }
        }
        .padding(GanchoTokens.Spacing.xl)
        .frame(width: 480)
        // Pin the height to the content's ideal. A fixed-width view with a
        // content-driven height inside a non-resizable NSWindow makes AppKit
        // loop its layout passes (the ">100 update passes" abort). Every other
        // hosted window pins both dimensions; this one only pinned width.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("paywall")
        .onAppear {
            // Funnel instrumentation, local counters (telemetry buckets
            // pick these up): paywall_shown by trigger.
            let key = "paywall-shown-\(trigger.rawValue)"
            UserDefaults.standard.set(
                UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
        }
    }

    private var paywallBody: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Text(LocalizedStringKey(copy.headline))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: GanchoTokens.Spacing.lg) {
                column(title: "Free forever", points: copy.freeForeverPoints)
                column(title: "Pro", points: copy.proPoints)
            }

            #if GANCHO_DIRECT_DOWNLOAD
                if LicenseSigningKey.isConfigured {
                    // Direct download: buy on Lemon Squeezy, then paste the key.
                    ActionButton(
                        "Get Gancho Pro", systemImage: "cart.fill", identifier: "buy-pro"
                    ) {
                        NSWorkspace.shared.open(LemonSqueezyStore.checkoutURL)
                    }
                    TextField("Paste your license key", text: $licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("license-key-field")
                    if let licenseError {
                        Text(LocalizedStringKey(licenseError))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    ActionButton(
                        "Activate", systemImage: "checkmark.seal.fill",
                        identifier: "activate-license"
                    ) {
                        Task { await activate() }
                    }
                    .disabled(
                        licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    // No signing key baked into this build, so activation can
                    // never succeed — be honest instead of dead-ending every key
                    // on "could not be activated".
                    Label(
                        "Pro is coming soon — purchases aren't open in this build yet.",
                        systemImage: "clock.badge"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pro-coming-soon")
                }
            #else
                if model.purchases.isPurchaseAvailable {
                    // Gancho Pro is a single one-time purchase; the live price
                    // comes from StoreKit once the product resolves.
                    ForEach(ProCatalog.all) { product in
                        ActionButton(
                            LocalizedStringKey("Upgrade — \(product.displayName)"),
                            systemImage: "star.fill",
                            identifier: "upgrade-\(product.plan.rawValue)"
                        ) {
                            model.buyPlan(product.plan)
                            dismiss()
                        }
                    }
                    Button("Restore purchases") {
                        model.restorePurchases()
                    }
                    .accessibilityIdentifier("restore-button")
                } else {
                    Text("In-app purchases are unavailable on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            #endif

            Button("Stay free") { dismiss() }
                .accessibilityIdentifier("stay-free-button")
        }
    }

    #if GANCHO_DIRECT_DOWNLOAD
        /// Validates the pasted key and reports the *specific* reason it didn't
        /// take, instead of one flat "couldn't activate" — a wrong/used-up key, a
        /// network problem, or a build that can't license. On success it shows the
        /// "Welcome to Pro" moment rather than dismissing in silence.
        private func activate() async {
            let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
            licenseError = nil
            switch await model.activateLicense(key) {
            case .activated:
                NSAccessibility.post(
                    element: NSApp as Any, notification: .announcementRequested,
                    userInfo: [
                        .announcement: String(localized: "Welcome to Pro. Everything is unlocked."),
                        .priority: NSAccessibilityPriorityLevel.high.rawValue,
                    ])
                didActivate = true
            case .invalidKey:
                licenseError =
                    "That key isn’t valid, or it’s already been used up. Double-check the key from your purchase email."
            case .networkUnavailable:
                licenseError =
                    "Couldn’t reach the license server. Check your connection and try again."
            case .storageUnavailable:
                licenseError =
                    "Your key is valid, but the license couldn’t be saved on this Mac. Check Keychain access and try again."
            case .notLicensable:
                licenseError = "Purchases aren’t open in this build yet."
            }
        }
    #endif

    /// The in-window success moment after activation: a one-time celebration of
    /// what just unlocked, then an explicit Done (no silent dismiss).
    private var welcomeToPro: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(GanchoTokens.Palette.success)
                .accessibilityHidden(true)
            Text("Welcome to Pro")
                .font(.title2.bold())
            Text("Everything is unlocked. Thanks for backing gancho.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                ForEach(copy.proPoints, id: \.self) { point in
                    Label(LocalizedStringKey(point), systemImage: "checkmark")
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(GanchoTokens.Spacing.sm)
            .ganchoSurface()
            ActionButton("Done", systemImage: "checkmark", identifier: "welcome-done") {
                dismiss()
            }
        }
        .accessibilityIdentifier("welcome-to-pro")
    }

    private func column(title: LocalizedStringKey, points: [String]) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            Text(title).font(.headline)
            ForEach(points, id: \.self) { point in
                Label(LocalizedStringKey(point), systemImage: "checkmark")
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GanchoTokens.Spacing.sm)
        .ganchoSurface()
    }
}

@MainActor
final class PaywallWindowController {
    private var window: NSWindow?

    func show(trigger: PaywallGatekeeper.Trigger, model: AppModel) {
        guard
            PaywallGatekeeper.shouldShow(
                trigger: trigger, tier: model.tier,
                hasPastedBackOnce: UserDefaults.standard.object(forKey: "first-pasteback-at")
                    != nil)
        else { return }
        let hosting = NSHostingController(
            rootView: PaywallView(trigger: trigger).environment(model).ganchoTinted())
        let created = NSWindow(contentViewController: hosting)
        created.title = String(localized: "Gancho Pro")
        created.styleMask = [.titled, .closable]
        created.isReleasedWhenClosed = false
        created.center()
        window = created
        created.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
