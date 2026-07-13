import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// The trust dashboard on iPhone: the clipboard-content telemetry boundary,
/// local counters from the on-device store, and an honest note on how capture
/// works on iOS. Every number is computed locally.
/// (macOS's Privacy Center has an "ignored" ledger and MCP log; iOS captures
/// only on explicit intent, so those don't apply here.)
struct IOSPrivacyCenterView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var captured = 0
    @State private var masked = 0
    @State private var expired = 0
    @State private var synced = 0

    private var weekAgo: Date { Date(timeIntervalSinceNow: -7 * 86_400) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "lock.shield.fill").font(.title2)
                        Spacer()
                        Text(verbatim: "0")
                            .font(.system(size: 44, weight: .bold))
                            .monospacedDigit()
                    }
                    Text("Clipboard-content analytics requests")
                        .font(.headline)
                    Text("Optional diagnostics contain anonymous counts and broad buckets only.")
                        .font(.footnote)
                        .opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(.vertical, GanchoTokens.Spacing.xs)
                .listRowBackground(Rectangle().fill(GanchoTokens.Palette.success.gradient))
            }

            Section("This week") {
                LabeledContent("Clips captured", value: "\(captured)")
                LabeledContent("Secrets masked", value: "\(masked)")
                LabeledContent("Items self-expired", value: "\(expired)")
                LabeledContent("Items synchronized", value: "\(synced)")
            }

            Section("Capture on iPhone") {
                Text(
                    // swiftlint:disable:next line_length
                    "Gancho never reads your pasteboard in the background. Capture happens only when you act: the save button, the share sheet, or a Shortcut."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Optional diagnostics") {
                Toggle(
                    "Share anonymous usage diagnostics",
                    isOn: Binding(
                        get: { model.telemetryConsent == .enabled },
                        set: { model.setTelemetryConsent($0 ? .enabled : .disabled) })
                )
                .accessibilityIdentifier("ios-telemetry-consent-toggle")
                Text(
                    // swiftlint:disable:next line_length
                    "Anonymous feature counts and broad performance buckets are off until you allow them. Clipboard content, titles, searches, and source-app names are never sent."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Recent issues") {
                let issues = Array(model.diagnostics.entries.reversed())
                if issues.isEmpty {
                    Text("No issues recorded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(issues) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.message).font(.footnote)
                            HStack(spacing: 4) {
                                Text(verbatim: entry.category)
                                Text(verbatim: "·")
                                Text(entry.at, format: .relative(presentation: .named))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Button("Copy for support") {
                        UIPasteboard.general.string =
                            issues
                            .map { "\($0.at): [\($0.category)] \($0.message)" }
                            .joined(separator: "\n")
                    }
                    .accessibilityIdentifier("copy-diagnostics")
                }
                Text("Recent technical issues only — content-free, nothing about your clips.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy Center")
        .accessibilityIdentifier("ios-privacy-center")
        .task { await refresh() }
    }

    /// Every counter is a local query against the on-device store. No network.
    private func refresh() async {
        captured = (try? await model.store.count()) ?? 0
        guard let full = model.full else { return }
        synced = (try? await full.syncedCount()) ?? 0
        expired = (try? await full.purgedItemCount(since: weekAgo)) ?? 0
        masked =
            (try? await full.search(
                ClipSearchQuery(text: "●●●●", mode: .exact), limit: 500
            ).count) ?? 0
    }
}
