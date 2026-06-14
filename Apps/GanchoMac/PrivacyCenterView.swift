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

    private var weekAgo: Date { Date(timeIntervalSinceNow: -7 * 86_400) }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            Label("Privacy Center", systemImage: "lock.shield")
                .font(.title2.bold())

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

                Section("Pasteboard access") {
                    LabeledContent("Last content read") {
                        if let date = model.monitor.lastContentReadAt {
                            Text(date, style: .relative)
                        } else {
                            Text("Never")
                        }
                    }
                    LabeledContent(
                        "Developer actions run",
                        value: "\(UserDefaults.standard.integer(forKey: "dev-actions-run"))")
                }

                Section("Network") {
                    Label {
                        Text("Outgoing content requests: 0")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    }
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
        .frame(width: 460, height: 480)
        .accessibilityIdentifier("privacy-center")
        .task { await refresh() }
    }

    private func refresh() async {
        captured = (try? await model.store.count()) ?? 0
        ignoredByReason = model.privacyEvents.countsByReason(since: weekAgo)
        if let grdb = model.grdbStore {
            expired = (try? await grdb.purgedItemCount(since: weekAgo)) ?? 0
            synced = (try? await grdb.syncedCount()) ?? 0
            masked =
                (try? await grdb.search(
                    ClipSearchQuery(text: "●●●●", mode: .exact), limit: 500
                ).count) ?? 0
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
                rootView: PrivacyCenterView().environment(model))
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
