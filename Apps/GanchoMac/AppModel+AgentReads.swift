import AppKit
import GanchoAppCore
import GanchoKit

/// Agent reads you can see: `gancho mcp` signals each logged access, and the
/// app reads the new ledger rows itself to light the menu-bar dot and show a HUD.
extension AppModel {
    nonisolated static let showsAgentReadsKey = "show-agent-reads"
    nonisolated private static let agentReadPage = 200

    /// Boards an active grant exposes, while local agent access is on.
    var agentExposedBoardIDs: Set<UUID> {
        guard mcpConfig.isEnabled else { return [] }
        return Set(mcpConfig.activeGrants.compactMap { $0.contextPack?.boardID })
    }

    func startAgentReadWatch() {
        guard let store = grdbForEngines else { return }
        _ = DistributedNotificationCenter.default().addObserver(
            forName: MCPAccessSignal.name, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.readAgentAccesses() }
        }
        Task {
            // Reads logged before this launch never show.
            agentReadFeed = AgentReadFeed(lastSeenID: (try? await store.latestMCPAccessID()) ?? 0)
            readAgentAccesses()
            #if DEBUG
                seedAgentReadIfRequested()
            #endif
        }
    }

    /// Opening the menu acknowledges the read.
    func acknowledgeAgentRead() {
        agentReadFeed?.clearDot()
        agentReadDotFade?.cancel()
        agentReadDotVisible = false
    }

    /// Signals can arrive many times a second; one read runs at a time and
    /// picks up whatever arrived meanwhile.
    private func readAgentAccesses() {
        guard agentReadFetch == nil else {
            agentReadFetchPending = true
            return
        }
        agentReadFetch = Task { [weak self] in
            repeat {
                self?.agentReadFetchPending = false
                await self?.ingestAgentAccesses()
            } while self?.agentReadFetchPending == true
            self?.agentReadFetch = nil
        }
    }

    private func ingestAgentAccesses() async {
        guard let store = grdbForEngines else { return }
        var notice: AgentReadFeed.Notice?
        while let lastSeen = agentReadFeed?.lastSeenID,
            let records = try? await store.mcpAccesses(after: lastSeen, limit: Self.agentReadPage),
            !records.isEmpty
        {
            mcpLedgerRevision += 1
            if let next = agentReadFeed?.ingest(records, now: .now) { notice = next }
            if records.count < Self.agentReadPage { break }
        }
        // A read during Private Mode or a share stays in the ledger only.
        guard let notice, showsAgentReads, copyHUD.isAllowed() else { return }
        agentReadDotVisible = true
        scheduleAgentReadDotFade()
        showAgentReadHUD(notice)
    }

    private func scheduleAgentReadDotFade() {
        agentReadDotFade?.cancel()
        guard let until = agentReadFeed?.dotUntil else { return }
        agentReadDotFade = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self else { return }
            agentReadDotVisible = agentReadFeed?.showsDot(at: .now) ?? false
        }
    }

    private func showAgentReadHUD(_ notice: AgentReadFeed.Notice) {
        let time = notice.occurredAt.formatted(date: .omitted, time: .shortened)
        let detail =
            notice.context.map { "\(MCPAccessLabels.context($0, boards: boards)) · \(time)" }
            ?? time
        var actions: [CopyHUDAction] = []
        if let grantID = notice.grantID,
            mcpConfig.grants.contains(where: { $0.id == grantID && $0.state() == .active })
        {
            actions.append(
                CopyHUDAction(id: "revoke", title: "Revoke", isDestructive: true) {
                    [weak self] in self?.revokeFromAgentReadHUD(grantID)
                })
        }
        copyHUD.show(
            CopyHUD(
                tile: .agent, title: Self.agentReadTitle(notice), detail: detail,
                identifier: "agent-read-hud", actions: actions))
    }

    private func revokeFromAgentReadHUD(_ grantID: UUID) {
        // A failed save already says so in a toast.
        guard revokeMCPGrant(id: grantID) else { return }
        copyHUD.show(CopyHUD(tile: .agent, title: "Access revoked", identifier: "agent-read-hud"))
    }

    static func agentReadTitle(_ notice: AgentReadFeed.Notice) -> LocalizedStringResource {
        let client = MCPAccessLabels.client(notice.clientName)
        let read = String(localized: "\(notice.reads) clips")
        let pinned = String(localized: "\(notice.pins) clips")
        switch (notice.reads > 0, notice.pins > 0) {
        case (true, true): return "\(client) read \(read) and pinned \(pinned)"
        case (false, true): return "\(client) pinned \(pinned)"
        default: return "\(client) read \(read)"
        }
    }

    #if DEBUG
        /// UI-test hook: the first seeded grant reads three clips, logged and
        /// signalled the way `gancho mcp` does it.
        private func seedAgentReadIfRequested() {
            guard CommandLine.arguments.contains("-seed-agent-read"),
                CommandLine.arguments.contains("-use-temp-durable-store"),
                let store = grdbForEngines, let grant = mcpConfig.activeGrants.first
            else { return }
            Task {
                try? await Task.sleep(for: .seconds(1))
                // A simulated share is picked up on the next 3 s poll; read during it.
                if CommandLine.arguments.contains("-simulate-screen-share") {
                    for _ in 0..<20 where sharingAppName == nil {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
                try? await store.recordMCPAccess(
                    MCPAccessEvent(
                        tool: .searchClips, scope: grant.scope, accessMode: grant.accessMode,
                        grantID: grant.id, clientName: grant.safeClientName, resultCount: 3,
                        context: grant.contextPack.map(MCPAccessContext.init)))
                MCPAccessSignal.post()
            }
        }
    #endif
}
