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

/// iOS settings: honest capture explainer + the Shortcuts gallery link.
/// The honest Pro screen for iOS — what Pro unlocks, the current free/Pro
/// state, and a real next step (restore a Universal Purchase, or learn where to
/// buy), so a free-tier limit no longer dead-ends on a note that vanishes.
/// Reachable from Settings and surfaced automatically when a limit is hit.
struct ProInfoView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var restoring = false
    @State private var restoreNote: String?
    private let copy = PaywallCopy.standard

    var body: some View {
        List {
            Section {
                HStack(spacing: GanchoTokens.Spacing.sm) {
                    Image(
                        systemName: model.tier == .pro ? "checkmark.seal.fill" : "seal"
                    )
                    .foregroundStyle(
                        model.tier == .pro ? GanchoTokens.Palette.success : Color.secondary)
                    Text(
                        model.tier == .pro
                            ? "You’re on Gancho Pro" : "You’re on the free plan"
                    )
                    .font(.headline)
                }
            }
            Section("What Pro unlocks") {
                ForEach(copy.proPoints, id: \.self) { point in
                    Label(LocalizedStringKey(point), systemImage: "checkmark")
                        .font(.callout)
                }
            }
            if model.tier != .pro {
                Section {
                    Link(destination: URL(string: "https://gancho.app/#pricing")!) {
                        Label("See Gancho Pro", systemImage: "cart")
                    }
                    .accessibilityIdentifier("see-pro")
                    Button {
                        Task { await restore() }
                    } label: {
                        if restoring {
                            ProgressView()
                        } else {
                            Label("Restore purchase", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(restoring)
                    .accessibilityIdentifier("restore-purchase")
                    if let restoreNote {
                        Text(LocalizedStringKey(restoreNote))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(
                        "Gancho Pro is a one-time purchase, available at gancho.app. Free stays free, forever."
                    )
                }
            }
        }
        .navigationTitle("Gancho Pro")
        .accessibilityIdentifier("pro-info")
    }

    private func restore() async {
        restoring = true
        restoreNote = nil
        let ok = await model.restorePro()
        restoring = false
        restoreNote =
            ok
            ? "Pro restored — enjoy."
            : "No purchase to restore on this Apple ID. Pro is sold at gancho.app."
    }
}
