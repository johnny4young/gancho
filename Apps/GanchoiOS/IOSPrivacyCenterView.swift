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
/// local receipt from the on-device store, and an honest note on how capture
/// works on iOS. Every number is computed locally.
struct IOSPrivacyCenterView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var receipt = PrivateActivityReceipt.empty()
    @State private var masked = 0
    @State private var synced = 0
    @State private var confirmsReceiptClear = false

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

            Section {
                LabeledContent("Items reused", value: "\(receipt.reusedItems)")
                    .accessibilityIdentifier("ios-private-receipt-reused-count")
                LabeledContent("Copies captured", value: "\(receipt.captures)")
                    .accessibilityIdentifier("ios-private-receipt-captured-count")
                LabeledContent("Captures skipped", value: "\(receipt.skippedCaptures)")
                    .accessibilityIdentifier("ios-private-receipt-skipped-count")
                LabeledContent(
                    "Protected copies skipped", value: "\(receipt.protectedCaptures)"
                )
                .accessibilityIdentifier("ios-private-receipt-protected-count")
                LabeledContent(
                    "Sensitive items self-expired", value: "\(receipt.sensitiveItemsExpired)"
                )
                .accessibilityIdentifier("ios-private-receipt-expired-count")
                Text(
                    // swiftlint:disable:next line_length
                    "Stored only on this iPhone for a rolling 13 months. Protected copies are included in skipped captures. Per-app totals never sync, export, or enter diagnostics."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                Button("Clear activity receipt", role: .destructive) {
                    confirmsReceiptClear = true
                }
                .tint(GanchoTokens.Palette.danger)
                .accessibilityIdentifier("ios-clear-private-receipt-button")
            } header: {
                Text("Private activity receipt")
                    .accessibilityIdentifier("ios-private-receipt-section")
            }

            Section("Activity by app") {
                if receipt.appStats.isEmpty {
                    Text("No per-app activity recorded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(receipt.appStats.enumerated()), id: \.offset) {
                        index, stat in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(stat.captures) captures")
                                Text("\(stat.reuses) reuses")
                            }
                            .monospacedDigit()
                        } label: {
                            if let bundleID = stat.bundleID {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: SourceApp.fallbackName(forBundleID: bundleID))
                                    Text(verbatim: bundleID)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Unknown app")
                            }
                        }
                        .accessibilityIdentifier("ios-private-receipt-app-\(index)-row")
                    }
                }
            }

            Section("On this iPhone now") {
                LabeledContent("Secrets masked", value: "\(masked)")
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
                LabeledContent(
                    "Successful reuses this session",
                    value: "\(model.telemetry.counts()["successful_reuse", default: 0])"
                )
                .accessibilityIdentifier("ios-successful-reuse-count")
                Text(
                    // swiftlint:disable:next line_length
                    "Anonymous feature counts and broad performance buckets are off until you allow them. Clipboard content, titles, searches, and source-app names are never sent."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text(
                    // swiftlint:disable:next line_length
                    "Session counts reset when Gancho quits. Turning diagnostics off also deletes the local activation receipt and terminates the analytics transport."
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
        .alert("Clear activity receipt?", isPresented: $confirmsReceiptClear) {
            Button("Clear receipt", role: .destructive) {
                Task {
                    await model.clearPrivateActivityReceipt()
                    await refresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases local activity totals. Your clips and settings stay unchanged.")
        }
    }

    /// Every counter is a local query against the on-device store. No network.
    private func refresh() async {
        receipt = await model.privateActivityReceipt()
        guard let full = model.full else { return }
        synced = (try? await full.syncedCount()) ?? 0
        masked = (try? await full.sensitiveCount()) ?? 0
    }
}
