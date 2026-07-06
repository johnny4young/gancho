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

/// First-run welcome (shown once via `ios-has-seen-welcome`). One scroll
/// screen: what Gancho is, then the three ways to save on iOS — because there
/// is no background clipboard watching, the save paths are the whole model.
struct IOSOnboardingView: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.lg) {
                    VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
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
            .navigationTitle("Welcome to Gancho")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Get started") {
                        // Persist the flag AND dismiss the sheet directly: the
                        // isPresented binding is derived from `hasSeenWelcome`, but
                        // dismissing explicitly guarantees the sheet closes even if
                        // the derived binding does not re-drive presentation.
                        onDone()
                        dismiss()
                    }
                    .accessibilityIdentifier("onboarding-done")
                }
            }
        }
    }

    private func onboardingRow(
        _ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.sm) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
