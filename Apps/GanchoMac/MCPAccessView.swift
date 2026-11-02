import AppKit
import ClipboardCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Per-client MCP authorization. Every active client is bound to an explicit
/// board/time context, expiry, exposure scope, and read/write choice. The
/// access ledger is metadata-only and revocation applies to the next call.
struct MCPAccessView: View {
    @Environment(AppModel.self) private var model
    @State private var log: [MCPAccessEvent] = []
    @State private var presentsNewGrant = false
    @State private var currentTime = Date.now

    private var enabled: Bool { model.mcpConfig.isEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            HStack {
                Label("MCP Access", systemImage: "terminal")
                    .font(.title2.bold())
                    .accessibilityIdentifier("mcp-access-header")
                Spacer()
                statusBadge
            }

            Form {
                serverSection
                clientsSection
                privacySection
                ledgerSection
            }
            .formStyle(.grouped)
        }
        .padding(GanchoTokens.Spacing.md)
        .buttonStyle(GanchoButtonStyle(.secondary))
        .frame(width: 620, height: 720)
        .sheet(isPresented: $presentsNewGrant) {
            NewMCPGrantView(boards: model.boards) { draft in
                _ = model.createMCPGrant(
                    clientName: draft.clientName,
                    scope: draft.scope,
                    accessMode: draft.accessMode,
                    board: draft.board,
                    timeScope: draft.timeScope,
                    expiresAt: draft.expiresAt)
                presentsNewGrant = false
            } onCancel: {
                presentsNewGrant = false
            }
        }
        .task(id: model.mcpLedgerRevision) {
            log = await model.recentMCPAccesses(limit: 30)
        }
        .task {
            await model.refreshBoards()
            while !Task.isCancelled {
                currentTime = .now
                log = await model.recentMCPAccesses(limit: 30)
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    break
                }
            }
        }
    }

    private var serverSection: some View {
        Section {
            Toggle(
                "Allow approved local AI clients",
                isOn: Binding(
                    get: { model.mcpConfig.isEnabled },
                    set: { model.setMCPEnabled($0) })
            )
            .accessibilityIdentifier("mcp-server-enabled-toggle")
            Text(
                "Each client gets its own expiring grant. No client can fall back to ambient history."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Local MCP server")
        }
    }

    private var clientsSection: some View {
        Section {
            if model.mcpConfig.grants.isEmpty {
                ContentUnavailableView(
                    "No approved clients",
                    systemImage: "person.badge.key",
                    description: Text("Add a client to select exactly what it may access.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(model.mcpConfig.grants) { grant in
                    clientRow(grant)
                }
            }

            Button("Add client…", systemImage: "plus") {
                presentsNewGrant = true
            }
            .disabled(model.boards.isEmpty)
            .accessibilityIdentifier("mcp-add-client-button")
        } header: {
            HStack {
                Text("Approved clients")
                Spacer()
                Text(
                    activeGrantCount == 1
                        ? "1 active" : "\(activeGrantCount) active"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
                .accessibilityIdentifier("mcp-active-client-count")
            }
        }
    }

    private var privacySection: some View {
        Section {
            Label {
                Text(
                    "Sensitive clips are vetoed for every client, including read-write grants."
                )
                .font(.footnote)
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(GanchoTokens.Palette.kindTint(for: .secret))
            }
            Label {
                Text("Revoke interrupts the client's next call without restarting its server.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "bolt.shield.fill")
                    .foregroundStyle(GanchoTokens.Palette.brandText)
            }
        } header: {
            Text("Privacy boundary")
        }
    }

    private var ledgerSection: some View {
        Section {
            if log.isEmpty {
                Text("No agent access yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(log.enumerated()), id: \.offset) { _, event in
                    ledgerRow(event)
                }
            }
        } header: {
            HStack {
                Text("Access ledger")
                Spacer()
                Text("Metadata only — never requests or clip content")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textCase(nil)
            }
        }
    }

    private func clientRow(_ grant: MCPClientGrant) -> some View {
        let state = grant.state(at: currentTime)
        let slug = identifierSlug(grant.safeClientName, fallback: grant.id.uuidString)
        return VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: grant.safeClientName)
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("mcp-client-name-\(slug)")
                stateBadge(state, slug: slug)
                Spacer()
                if state == .active {
                    Button("Copy server command") {
                        SystemPasteboardWriter().write(
                            .text(connectionCommand(for: grant)), asPlainText: true)
                        model.toasts.show(GanchoToast(message: "Copied"))
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("mcp-copy-command-\(slug)")
                    Button("Revoke", role: .destructive) {
                        model.revokeMCPGrant(id: grant.id)
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("mcp-revoke-client-\(slug)")
                }
            }

            HStack(spacing: GanchoTokens.Spacing.sm) {
                policyBadge(
                    accessModeLabel(grant.accessMode), tint: accessModeTint(grant.accessMode))
                policyBadge(scopeLabel(grant.scope), tint: .secondary)
                if let context = grant.contextPack {
                    Label(contextLabel(context), systemImage: "rectangle.stack")
                }
                Spacer(minLength: 0)
                expiryLabel(grant)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if state == .active {
                Text(verbatim: connectionCommand(for: grant))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, GanchoTokens.Spacing.xxs)
    }

    /// Client · tool · context at call time · clips · time, as the call ran.
    private func ledgerRow(_ event: MCPAccessEvent) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: MCPAccessLabels.client(event.clientName))
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            Text(verbatim: event.tool.rawValue)
                .font(.caption.monospaced())
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            Text(verbatim: ledgerScope(event))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .trailing) {
                if event.wasDenied {
                    Text("Denied").foregroundStyle(GanchoTokens.Palette.warningInk)
                } else if event.resultCount > 0 {
                    Text("\(event.resultCount) clips")
                }
            }
            .frame(width: 64, alignment: .trailing)
            Text(verbatim: ledgerTime(event.occurredAt))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mcp-ledger-row")
    }

    private func ledgerScope(_ event: MCPAccessEvent) -> String {
        if let denial = event.denialReason {
            return denial.rawValue
        }
        if let context = event.context {
            return MCPAccessLabels.context(context, boards: model.boards)
        }
        return String(localized: scopeLabel(event.scope))
    }

    private func ledgerTime(_ date: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: currentTime)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(enabled ? GanchoTokens.Palette.success : Color.secondary)
                .frame(width: 7, height: 7)
            Text(enabled ? "On" : "Off")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(enabled ? GanchoTokens.Palette.brandText : Color.secondary)
    }

    private var activeGrantCount: Int {
        model.mcpConfig.grants.count(where: { grant in
            grant.state(at: currentTime) == .active && grant.contextPack?.isExplicit == true
        })
    }

    private func stateBadge(_ state: MCPGrantState, slug: String) -> some View {
        let presentation: (LocalizedStringKey, Color) =
            switch state {
            case .active: ("Active", GanchoTokens.Palette.success)
            case .expired: ("Expired", GanchoTokens.Palette.warning)
            case .revoked: ("Revoked", GanchoTokens.Palette.danger)
            }
        return Text(presentation.0)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 2)
            .ganchoTintedPill(presentation.1, wash: 0.12)
            .accessibilityIdentifier("mcp-client-state-\(slug)")
    }

    private func policyBadge(_ text: LocalizedStringResource, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .ganchoTintedPill(tint, wash: 0.1)
    }

    @ViewBuilder private func expiryLabel(_ grant: MCPClientGrant) -> some View {
        if let expiresAt = grant.expiresAt {
            Text(expiresAt, format: .relative(presentation: .named))
        } else {
            Text("No expiry")
        }
    }

    private func accessModeTint(_ mode: MCPAccessMode) -> Color {
        mode == .readWrite ? GanchoTokens.Palette.warning : GanchoTokens.Palette.success
    }

    private func accessModeLabel(_ mode: MCPAccessMode) -> LocalizedStringResource {
        switch mode {
        case .readOnly: "Read only"
        case .readWrite: "Read and organize"
        }
    }

    private func scopeLabel(_ scope: MCPAccessScope) -> LocalizedStringResource {
        switch scope {
        case .metadata: "Metadata only"
        case .boards: "Marked clips"
        case .all: "Full content in context"
        }
    }

    private func contextLabel(_ context: MCPContextPack) -> String {
        let board = context.boardName ?? context.name
        return "\(board) · \(MCPAccessLabels.timeScope(context.timeScope))"
    }

    private func connectionCommand(for grant: MCPClientGrant) -> String {
        "gancho mcp --grant \(grant.id.uuidString)"
    }

    private func identifierSlug(_ value: String, fallback: String) -> String {
        let slug = value.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return slug.isEmpty ? fallback.lowercased() : slug
    }
}

private struct NewMCPGrantView: View {
    struct Draft {
        let clientName: String
        let scope: MCPAccessScope
        let accessMode: MCPAccessMode
        let board: Pinboard
        let timeScope: MCPTimeScope
        let expiresAt: Date
    }

    let boards: [Pinboard]
    let onCreate: (Draft) -> Void
    let onCancel: () -> Void

    @State private var clientName = ""
    @State private var scope = MCPAccessScope.metadata
    @State private var accessMode = MCPAccessMode.readOnly
    @State private var boardID: UUID?
    @State private var timeScope = MCPTimeScope.lastWeek
    @State private var duration = GrantDuration.oneWeek

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            Label("Approve a local AI client", systemImage: "person.badge.key")
                .font(.title2.bold())
                .accessibilityIdentifier("mcp-new-client-header")
            Text("Choose the smallest context and shortest duration that client needs.")
                .foregroundStyle(.secondary)

            Form {
                TextField("Client name", text: $clientName)
                    .accessibilityIdentifier("mcp-new-client-name-field")
                Picker("Board context", selection: $boardID) {
                    ForEach(boards) { board in
                        board.displayTitle.tag(Optional(board.id))
                    }
                }
                .accessibilityIdentifier("mcp-new-client-board-picker")
                Picker("Time window", selection: $timeScope) {
                    Text("Last hour").tag(MCPTimeScope.lastHour)
                    Text("Last day").tag(MCPTimeScope.lastDay)
                    Text("Last 7 days").tag(MCPTimeScope.lastWeek)
                    Text("Last 30 days").tag(MCPTimeScope.lastMonth)
                    Text("All time").tag(MCPTimeScope.allTime)
                }
                Picker("Content access", selection: $scope) {
                    Text("Metadata only").tag(MCPAccessScope.metadata)
                    Text("Marked clips").tag(MCPAccessScope.boards)
                    Text("Full content in context").tag(MCPAccessScope.all)
                }
                Picker("Actions", selection: $accessMode) {
                    Text("Read only").tag(MCPAccessMode.readOnly)
                    Text("Read and organize").tag(MCPAccessMode.readWrite)
                }
                Picker("Expires", selection: $duration) {
                    ForEach(GrantDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }
            }
            .formStyle(.grouped)

            Label(
                "Secrets remain blocked. Read-write only permits organization inside this context.",
                systemImage: "lock.shield"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Create grant") {
                    guard let board else { return }
                    onCreate(
                        Draft(
                            clientName: clientName.trimmingCharacters(
                                in: .whitespacesAndNewlines),
                            scope: scope,
                            accessMode: accessMode,
                            board: board,
                            timeScope: timeScope,
                            expiresAt: Date().addingTimeInterval(duration.interval)))
                }
                .keyboardShortcut(.defaultAction)
                .ganchoButtonStyle(.primary)
                .disabled(trimmedClientName.isEmpty || board == nil)
                .accessibilityIdentifier("mcp-create-grant-button")
            }
        }
        .padding(GanchoTokens.Spacing.lg)
        .frame(width: 500, height: 560)
        .onAppear { boardID = boardID ?? boards.first?.id }
    }

    private var trimmedClientName: String {
        clientName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var board: Pinboard? {
        boardID.flatMap { id in boards.first(where: { $0.id == id }) }
    }

    private enum GrantDuration: String, CaseIterable, Identifiable {
        case oneHour, oneDay, oneWeek, oneMonth

        var id: String { rawValue }
        var interval: TimeInterval {
            switch self {
            case .oneHour: 60 * 60
            case .oneDay: 24 * 60 * 60
            case .oneWeek: 7 * 24 * 60 * 60
            case .oneMonth: 30 * 24 * 60 * 60
            }
        }
        var label: LocalizedStringKey {
            switch self {
            case .oneHour: "1 hour"
            case .oneDay: "1 day"
            case .oneWeek: "7 days"
            case .oneMonth: "30 days"
            }
        }
    }
}

/// Window host for the MCP Access screen (menu-bar agent, no WindowGroup).
@MainActor
final class MCPAccessWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: MCPAccessView().environment(model).ganchoTinted())
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "MCP Access")
            created.styleMask = [.titled, .closable, .resizable]
            created.isReleasedWhenClosed = false
            created.sizeToFitContentAndCenter()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
