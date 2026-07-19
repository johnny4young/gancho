import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Privacy made verifiable, not promised: local counters, the last content
/// read, and the telemetry boundary. Every number is computed on this Mac;
/// optional diagnostics never carry clipboard content.
struct PrivacyCenterView: View {
    @Environment(AppModel.self) private var model
    @State private var receipt = PrivateActivityReceipt.empty()
    @State private var masked = 0
    @State private var synced = 0
    @State private var confirmsReceiptClear = false
    @State private var mcpAccesses: [MCPAccessEvent] = []
    @State private var mcpCalls = 0
    @State private var mcpResultsReturned = 0
    @State private var mcpDenied = 0

    private var weekAgo: Date { Date(timeIntervalSinceNow: -7 * 86_400) }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            Label("Privacy Center", systemImage: "lock.shield")
                .font(.title2.bold())

            heroClaim

            if model.storageIsEphemeral {
                // The counters below all read 0 on the in-memory fallback; say so
                // rather than let the dashboard imply nothing is happening.
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("History isn't being saved").font(.body.weight(.semibold))
                        Text(
                            // swiftlint:disable:next line_length
                            "Gancho is on a temporary store, so these numbers reset on quit and your clips won't persist."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(GanchoTokens.Palette.danger)
                }
                .padding(GanchoTokens.Spacing.sm)
                .background(
                    GanchoTokens.Palette.danger.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                )
                .accessibilityIdentifier("privacy-storage-warning")
            }

            Form {
                Section {
                    LabeledContent("Items reused", value: "\(receipt.reusedItems)")
                        .accessibilityIdentifier("private-receipt-reused-count")
                    LabeledContent("Copies captured", value: "\(receipt.captures)")
                        .accessibilityIdentifier("private-receipt-captured-count")
                    LabeledContent("Captures skipped", value: "\(receipt.skippedCaptures)")
                        .accessibilityIdentifier("private-receipt-skipped-count")
                    LabeledContent(
                        "Protected copies skipped", value: "\(receipt.protectedCaptures)"
                    )
                    .accessibilityIdentifier("private-receipt-protected-count")
                    LabeledContent(
                        "Sensitive items self-expired",
                        value: "\(receipt.sensitiveItemsExpired)"
                    )
                    .accessibilityIdentifier("private-receipt-expired-count")
                    Text(
                        // swiftlint:disable:next line_length
                        "Stored only on this Mac for a rolling 13 months. Protected copies are included in skipped captures. Per-app totals never sync, export, or enter diagnostics."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Button("Clear activity receipt", role: .destructive) {
                        confirmsReceiptClear = true
                    }
                    .tint(GanchoTokens.Palette.danger)
                    .accessibilityIdentifier("clear-private-receipt-button")
                } header: {
                    Text("Private activity receipt")
                        .accessibilityIdentifier("private-receipt-section")
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
                                        Text(verbatim: SourceApp.displayName(forBundleID: bundleID))
                                        Text(verbatim: bundleID)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Unknown app")
                                }
                            }
                            .accessibilityIdentifier("private-receipt-app-\(index)-row")
                        }
                    }
                }

                Section("On this Mac now") {
                    LabeledContent("Secrets masked", value: "\(masked)")
                    LabeledContent("Items synchronized", value: "\(synced)")
                }

                Section("iCloud sync") {
                    SyncStatusView(status: model.syncStatus, showsSuggestion: true)
                    Button("Force sync") { model.forceSync() }
                        .accessibilityIdentifier("force-sync")
                    ForEach(
                        Array(model.privacyEvents.recentSyncEvents(limit: 8).enumerated()),
                        id: \.offset
                    ) { _, event in
                        LabeledContent {
                            Text(event.occurredAt, style: .time)
                        } label: {
                            Label(syncEventTitle(event), systemImage: syncEventSymbol(event.kind))
                        }
                    }
                }

                Section("Local AI agent access (MCP)") {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(
                                    model.mcpConfig.isEnabled
                                        ? GanchoTokens.Palette.success : Color.secondary
                                )
                                .frame(width: 7, height: 7)
                            Text(model.mcpConfig.isEnabled ? "On" : "Off")
                        }
                    }
                    LabeledContent("Agent calls this week", value: "\(mcpCalls)")
                    LabeledContent("Agent results returned", value: "\(mcpResultsReturned)")
                    LabeledContent("Denied by scope or veto", value: "\(mcpDenied)")
                    Button("Open MCP Access…") { model.mcpAccessWindow.show(model: model) }
                        .accessibilityIdentifier("open-mcp-access")
                    if mcpAccesses.isEmpty {
                        Text("No agent access yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(mcpAccesses.prefix(5).enumerated()), id: \.offset) {
                            _, event in
                            LabeledContent {
                                HStack {
                                    if event.wasDenied {
                                        Text("Denied")
                                            .font(.caption)
                                            .foregroundStyle(GanchoTokens.Palette.warning)
                                    }
                                    Text(event.occurredAt, style: .time)
                                }
                            } label: {
                                Label {
                                    HStack(spacing: GanchoTokens.Spacing.xs) {
                                        Text(
                                            verbatim: event.clientName
                                                ?? String(localized: "Unknown client"))
                                        Text(verbatim: event.tool.rawValue).monospaced()
                                    }
                                } icon: {
                                    Image(systemName: mcpToolSymbol(event.tool))
                                }
                            }
                        }
                    }
                }

                Section("Pasteboard access") {
                    LabeledContent("Last content read") {
                        if let date = model.monitor.lastContentReadAt {
                            Text(date, style: .relative)
                        } else {
                            Text("Never")
                        }
                    }
                    #if DEBUG
                        // Internal usage counter — useful while developing, but it
                        // reads as debug instrumentation in a user-facing privacy
                        // dashboard, so keep it out of release builds.
                        LabeledContent(
                            "Developer actions run",
                            value: "\(UserDefaults.standard.integer(forKey: "dev-actions-run"))")
                    #endif
                }

                Section("Recent issues") {
                    let issues = Array(model.diagnostics.entries.reversed())
                    if issues.isEmpty {
                        Text("No issues recorded.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(issues) { entry in
                            LabeledContent {
                                Text(entry.at, style: .time)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: entry.message)
                                    Text(verbatim: entry.category)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Copy for support") {
                            let dump =
                                issues
                                .map { "\($0.at): [\($0.category)] \($0.message)" }
                                .joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(dump, forType: .string)
                        }
                        .accessibilityIdentifier("copy-diagnostics")
                    }
                    Text("Recent technical issues only — content-free, nothing about your clips.")
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
                    .accessibilityIdentifier("privacy-telemetry-consent-toggle")
                    LabeledContent(
                        "Successful reuses this session",
                        value: "\(model.telemetry.counts()["successful_reuse", default: 0])"
                    )
                    .accessibilityIdentifier("privacy-successful-reuse-count")
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

                Section("Network") {
                    Text(
                        // swiftlint:disable:next line_length
                        "Gancho never sends clipboard content to analytics. Optional iCloud sync uses your private iCloud account; verify the boundary with Little Snitch or any network monitor."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 480, height: 620)
        .accessibilityIdentifier("privacy-center")
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

    private func refresh() async {
        receipt = await model.privateActivityReceipt()
        if let grdb = model.grdbStore {
            synced = (try? await grdb.syncedCount()) ?? 0
            masked = (try? await grdb.sensitiveCount()) ?? 0
        }
        let recent = await model.recentMCPAccesses(limit: 50)
        mcpAccesses = recent
        let thisWeek = recent.filter { $0.occurredAt >= weekAgo }
        mcpCalls = thisWeek.count
        mcpResultsReturned = thisWeek.reduce(0) { $0 + $1.resultCount }
        mcpDenied = thisWeek.filter(\.wasDenied).count
    }

    /// The trust headline: clipboard content never enters analytics, regardless
    /// of the optional diagnostics consent state.
    private var heroClaim: some View {
        HStack(spacing: GanchoTokens.Spacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "0").font(.system(size: 30, weight: .bold))
                Text("clipboard-content analytics requests").font(.headline)
                Text("Optional diagnostics contain anonymous counts and broad buckets only.")
                    .font(.caption)
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(GanchoTokens.Spacing.md)
        .background(
            GanchoTokens.Palette.success.gradient,
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous))
    }

    private func mcpToolSymbol(_ tool: MCPToolName) -> String {
        switch tool {
        case .searchClips: "magnifyingglass"
        case .getClip: "doc.text"
        case .createPin: "pin"
        case .pasteStack: "square.stack"
        case .listBoards: "rectangle.stack"
        }
    }

    private func syncEventTitle(_ event: SyncActivityEvent) -> LocalizedStringKey {
        switch event.kind {
        case .synced: "Synced"
        case .paused, .failed: event.cause.map { SyncStatusView.causeText($0) } ?? "Sync error"
        }
    }

    private func syncEventSymbol(_ kind: SyncActivityKind) -> String {
        switch kind {
        case .synced: "checkmark.icloud"
        case .paused: "pause.circle"
        case .failed: "exclamationmark.icloud"
        }
    }

}

/// Window host for the Privacy Center (menu-bar agent, no WindowGroup).
@MainActor
final class PrivacyCenterWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: PrivacyCenterView().environment(model).ganchoTinted())
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "Privacy Center")
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
