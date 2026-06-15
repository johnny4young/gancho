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
        try MCPServerConfig(isEnabled: true, scope: .all).save(toStoreDirectory: directory)
        let loaded = MCPServerConfig.load(fromStoreDirectory: directory)
        #expect(loaded.isEnabled == true)
        #expect(loaded.scope == .all)
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
                tool: .getClip, scope: .metadata, wasDenied: true,
                occurredAt: Date(timeIntervalSince1970: 2_000)))

        let events = try await store.recentMCPAccesses(limit: 10)
        #expect(events.count == 2)
        #expect(events.first?.tool == .getClip)
        #expect(events.first?.wasDenied == true)
        #expect(events.last?.resultCount == 3)
    }
}
