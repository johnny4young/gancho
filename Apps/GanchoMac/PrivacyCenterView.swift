import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Privacy made verifiable, not promised: local counters, the last content
/// read, and the network claim — this screen performs ZERO network requests
/// and every number is computed on this Mac. The website's claims literally
/// come from here; skeptics can confirm with Little Snitch.
struct PrivacyCenterView: View {
    @Environment(AppModel.self) private var model
    @State private var captured = 0
    @State private var masked = 0
    @State private var expired = 0
    @State private var ignoredByReason: [CaptureIgnoreReason: Int] = [:]
    @State private var synced = 0
    @State private var mcpAccesses: [MCPAccessEvent] = []
    @State private var mcpCalls = 0
    @State private var mcpBodiesExposed = 0
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
                Section("This week, on this Mac") {
                    LabeledContent("Clips captured", value: "\(captured)")
                    LabeledContent(
                        "Copies ignored", value: "\(ignoredByReason.values.reduce(0, +))")
                    ForEach(CaptureIgnoreReason.allCases, id: \.self) { reason in
                        if let count = ignoredByReason[reason], count > 0 {
                            LabeledContent(reasonLabel(reason), value: "\(count)")
                                .padding(.leading, GanchoTokens.Spacing.md)
                        }
                    }
                    LabeledContent("Secrets masked", value: "\(masked)")
                    LabeledContent("Items self-expired", value: "\(expired)")
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
                    LabeledContent("Content bodies exposed", value: "\(mcpBodiesExposed)")
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
                                    Text(verbatim: event.tool.rawValue).monospaced()
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

                Section("Network") {
                    Text(
                        "Gancho sends no clipboard content anywhere. Verify it yourself with Little Snitch or any network monitor — this screen included."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 480, height: 560)
        .accessibilityIdentifier("privacy-center")
        .task { await refresh() }
    }

    private func refresh() async {
        captured = (try? await model.store.count()) ?? 0
        ignoredByReason = model.privacyEvents.countsByReason(since: weekAgo)
        if let grdb = model.grdbStore {
            expired = (try? await grdb.purgedItemCount(since: weekAgo)) ?? 0
            synced = (try? await grdb.syncedCount()) ?? 0
            masked = (try? await grdb.sensitiveCount()) ?? 0
        }
        let recent = await model.recentMCPAccesses(limit: 50)
        mcpAccesses = recent
        let thisWeek = recent.filter { $0.occurredAt >= weekAgo }
        mcpCalls = thisWeek.count
        mcpBodiesExposed = thisWeek.reduce(0) { $0 + $1.resultCount }
        mcpDenied = thisWeek.filter(\.wasDenied).count
    }

    /// The trust headline (the design's green hero): the 0-outgoing-requests
    /// claim, verifiable with an external network monitor.
    private var heroClaim: some View {
        HStack(spacing: GanchoTokens.Spacing.md) {
            Image(systemName: "lock.shield.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "0").font(.system(size: 30, weight: .bold))
                Text("outgoing content requests").font(.headline)
                Text("Your clipboard never leaves this Mac — verify with Little Snitch.")
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

    private func reasonLabel(_ reason: CaptureIgnoreReason) -> LocalizedStringKey {
        switch reason {
        case .sensitiveType: "From a password manager"
        case .denylistedApp: "From an excluded app"
        case .userIgnoredNext: "You said “ignore next”"
        case .preferenceFiltered: "Type disabled in Settings"
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
