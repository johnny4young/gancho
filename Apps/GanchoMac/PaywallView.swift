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

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Text(LocalizedStringKey(copy.headline))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: GanchoTokens.Spacing.lg) {
                column(title: "Free forever", points: copy.freeForeverPoints)
                column(title: "Pro", points: copy.proPoints)
            }

            #if GANCHO_DIRECT_DOWNLOAD
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
                    Task {
                        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if await model.activateLicense(key) {
                            dismiss()
                        } else {
                            licenseError = "That license key could not be activated."
                        }
                    }
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
