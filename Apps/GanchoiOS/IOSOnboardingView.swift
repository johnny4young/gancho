import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// First-run welcome (shown once via `ios-has-seen-welcome`). Page 1 is what
/// Gancho is and the three ways to save; page 2 shows the sensed row the user
/// is about to meet and lets them try the system Paste button right there.
struct IOSOnboardingView: View {
    let onDone: () -> Void
    /// A paste on page 2 saved this row; the sheet closes and the app opens it.
    let onSaved: (ClipItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsSensedPage = false

    var body: some View {
        NavigationStack {
            welcomePage
                .navigationTitle("Welcome to Gancho")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Next") { showsSensedPage = true }
                            .accessibilityIdentifier("onboarding-next")
                    }
                }
                .navigationDestination(isPresented: $showsSensedPage) {
                    IOSOnboardingSensedPage(
                        onBack: { showsSensedPage = false }, onDone: finish,
                        onSaved: { clip in
                            onSaved(clip)
                            finish()
                        })
                }
        }
        // Toolbar text in the readable green ink, not the 2.2:1 brand fill.
        .ganchoInkTint()
    }

    private func finish() {
        // Persist the flag AND dismiss the sheet directly: the isPresented
        // binding is derived from `hasSeenWelcome`, but dismissing explicitly
        // guarantees the sheet closes even if the binding does not re-drive it.
        onDone()
        dismiss()
    }

    private var welcomePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.lg) {
                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(GanchoTokens.Palette.accentInk)
                    Text("Everything you copy, saved and searchable")
                        .font(.title2.bold())
                    Text(
                        "Gancho keeps a private history of what you copy — all on this device."
                    )
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
                    Text("Three ways to save")
                        .font(.headline)
                    onboardingRow(
                        "hand.tap", "Tap to save",
                        // swiftlint:disable:next line_length
                        "iOS can't watch the clipboard in the background — no app can. Use the Paste button to save what you copied."
                    )
                    onboardingRow(
                        "square.and.arrow.up", "Share from any app",
                        "Send text, a link, or an image to Gancho from the share sheet.")
                    onboardingRow(
                        "bolt", "Shortcuts & Action Button",
                        "Save your clipboard with a Shortcut — even from the Action Button.")
                }

                Label(
                    "Nothing leaves this device unless you turn on iCloud sync.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func onboardingRow(
        _ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(GanchoTokens.Palette.accentInk)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
