import AppKit
import GanchoDesign
import GanchoKit
import SwiftUI

/// The contextual paywall: only ever AFTER the first successful paste-back
/// (gatekeeper rule), never as a gateway. No dark patterns — "Stay free"
/// is always visible and free really is forever.
struct PaywallView: View {
    let trigger: PaywallGatekeeper.Trigger
    @Environment(\.dismiss) private var dismiss

    private let copy = PaywallCopy.standard
    private let purchases: any PurchaseHandling = UnavailablePurchaseHandler()

    var body: some View {
        VStack(spacing: GanchoTokens.Spacing.md) {
            Text(LocalizedStringKey(copy.headline))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: GanchoTokens.Spacing.lg) {
                column(title: "Free forever", points: copy.freeForeverPoints)
                column(title: "Pro", points: copy.proPoints)
            }

            if purchases.isPurchaseAvailable {
                ActionButton(
                    "Upgrade to Pro", systemImage: "star.fill", identifier: "upgrade-button"
                ) {
                    UserDefaults.standard.set(
                        UserDefaults.standard.integer(forKey: "upgrade-started") + 1,
                        forKey: "upgrade-started")
                    Task { try? await purchases.purchasePro() }
                }
            } else {
                Text("Pro purchases arrive with the public launch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Stay free") { dismiss() }
                .accessibilityIdentifier("stay-free-button")
        }
        .padding(GanchoTokens.Spacing.xl)
        .frame(width: 480)
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
        let hosting = NSHostingController(rootView: PaywallView(trigger: trigger))
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
