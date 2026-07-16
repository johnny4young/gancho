import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP config + Privacy Center access log")
struct MCPConfigTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-cfg-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("config defaults to OFF / metadata — opt-in by absence")
    func defaults() {
        let config = MCPServerConfig()
        #expect(config.isEnabled == false)
        #expect(config.scope == .metadata)
    }

    @Test("a missing config file loads as disabled")
    func missingFileIsDisabled() {
        let config = MCPServerConfig.load(fromStoreDirectory: tempDirectory())
        #expect(config.isEnabled == false)
    }

    @Test("save then load round-trips enabled state and scope")
    func roundTrip() throws {
        let directory = tempDirectory()
        let grantID = UUID()
        let boardID = UUID()
        let grant = MCPClientGrant(
            id: grantID,
            clientName: "Claude Desktop",
            scope: .all,
            accessMode: .readWrite,
            contextPack: MCPContextPack(
                name: "Work · last week",
                boardID: boardID,
                boardName: "Work",
                timeScope: .lastWeek),
            createdAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date(timeIntervalSince1970: 2_000))
        try MCPServerConfig(isEnabled: true, scope: .all, grants: [grant])
            .save(toStoreDirectory: directory)
        let loaded = MCPServerConfig.load(fromStoreDirectory: directory)
        #expect(loaded.isEnabled == true)
        #expect(loaded.scope == .all)
        #expect(loaded.schemaVersion == MCPServerConfig.currentSchemaVersion)
        #expect(loaded.grants == [grant])

        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent(MCPServerConfig.fileName).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("legacy ambient config migrates disabled instead of authorizing every client")
    func legacyConfigFailsClosed() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"isEnabled":true,"scope":"all"}"#.utf8)
            .write(to: directory.appendingPathComponent(MCPServerConfig.fileName))

        let loaded = MCPServerConfig.load(fromStoreDirectory: directory)

        #expect(loaded.schemaVersion == MCPServerConfig.currentSchemaVersion)
        #expect(loaded.isEnabled == false)
        #expect(loaded.grants.isEmpty)
    }

    @Test("unsupported future config fails closed")
    func futureConfigFailsClosed() throws {
        let directory = tempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(
            #"{"schemaVersion":999,"isEnabled":true,"scope":"all","grants":[]}"#.utf8
        ).write(to: directory.appendingPathComponent(MCPServerConfig.fileName))

        let loaded = MCPServerConfig.load(fromStoreDirectory: directory)

        #expect(loaded.schemaVersion == MCPServerConfig.currentSchemaVersion)
        #expect(loaded.isEnabled == false)
        #expect(loaded.grants.isEmpty)
    }

    @Test("grant resolution distinguishes every fail-closed state")
    func grantResolution() {
        let now = Date(timeIntervalSince1970: 10_000)
        let boardID = UUID()
        let active = MCPClientGrant(
            clientName: "Active",
            contextPack: MCPContextPack(name: "Board", boardID: boardID),
            expiresAt: now.addingTimeInterval(60))
        var expired = active
        expired.id = UUID()
        expired.expiresAt = now
        var revoked = active
        revoked.id = UUID()
        revoked.revokedAt = now
        let invalid = MCPClientGrant(clientName: "Ambient")
        let oversized = MCPClientGrant(
            clientName: "Oversized",
            contextPack: MCPContextPack(
                name: "Too many clips",
                clipIDs: Set(
                    (0...MCPContextPack.maximumCuratedClipCount).map { _ in UUID() })))
        let config = MCPServerConfig(
            isEnabled: true, grants: [active, expired, revoked, invalid, oversized])

        #expect(config.resolveGrant(id: active.id, at: now) == .active(active))
        #expect(config.resolveGrant(id: expired.id, at: now) == .expired(expired))
        #expect(config.resolveGrant(id: revoked.id, at: now) == .revoked(revoked))
        #expect(config.resolveGrant(id: invalid.id, at: now) == .invalidContext(invalid))
        #expect(config.resolveGrant(id: oversized.id, at: now) == .invalidContext(oversized))
        #expect(config.resolveGrant(id: UUID(), at: now) == .missing)
        #expect(
            MCPServerConfig(isEnabled: false, grants: [active])
                .resolveGrant(id: active.id, at: now) == .disabled(active))
    }

    @Test("access log persists metadata and reads newest first")
    func accessLogRoundTrips() async throws {
        let store = try MCPTestStore.make()
        try await store.recordMCPAccess(
            MCPAccessEvent(
                tool: .searchClips, scope: .all, resultCount: 3,
                occurredAt: Date(timeIntervalSince1970: 1_000)))
        try await store.recordMCPAccess(
            MCPAccessEvent(
                tool: .getClip,
                scope: .metadata,
                accessMode: .readOnly,
                grantID: UUID(uuidString: "A1000000-0000-4000-A000-000000000001"),
                clientName: "Claude Desktop",
                wasDenied: true,
                denialReason: .scope,
                occurredAt: Date(timeIntervalSince1970: 2_000)))

        let events = try await store.recentMCPAccesses(limit: 10)
        #expect(events.count == 2)
        #expect(events.first?.tool == .getClip)
        #expect(events.first?.wasDenied == true)
        #expect(events.first?.accessMode == .readOnly)
        #expect(events.first?.clientName == "Claude Desktop")
        #expect(events.first?.denialReason == .scope)
        #expect(events.last?.resultCount == 3)
    }
}
