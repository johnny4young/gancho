import Foundation
import Testing

@testable import GanchoKit

@Suite("MCP access scope — elevation surface")
struct MCPAccessScopeTests {
    @Test("metadata scope is not elevated; content-exposing scopes are")
    func elevationTracksContentExposure() {
        #expect(MCPServerConfig(isEnabled: true, scope: .metadata).isElevated == false)
        #expect(MCPServerConfig(isEnabled: true, scope: .boards).isElevated == true)
        #expect(MCPServerConfig(isEnabled: true, scope: .all).isElevated == true)
    }

    @Test("the default (opt-in-by-absence) config is not elevated")
    func defaultConfigIsNotElevated() {
        #expect(MCPServerConfig().isElevated == false)
    }

    @Test("context packs require an explicit board or curated clips and honor rolling time")
    func contextPackBounds() {
        let now = Date(timeIntervalSince1970: 100_000)
        let boardID = UUID()
        let recent = ClipItem(id: UUID(), createdAt: now.addingTimeInterval(-30 * 60))
        let old = ClipItem(id: UUID(), createdAt: now.addingTimeInterval(-2 * 60 * 60))
        let pack = MCPContextPack(
            name: "Recent board", boardID: boardID, timeScope: .lastHour)

        #expect(MCPContextPack(name: "Ambient").isExplicit == false)
        #expect(pack.contains(item: recent, boardIDs: [boardID], now: now))
        #expect(!pack.contains(item: recent, boardIDs: [], now: now))
        #expect(!pack.contains(item: old, boardIDs: [boardID], now: now))
    }

    @Test("a revision-bound pack rejects a clip changed after review")
    func revisionBoundPack() throws {
        let now = Date(timeIntervalSince1970: 100_000)
        let reviewed = ClipItem(createdAt: now, contentHash: "reviewed")
        var edited = reviewed
        edited.contentHash = "edited"
        // A text edit keeps the dedupe hash but always advances updatedAt.
        var editedInPlace = reviewed
        editedInPlace.updatedAt = now.addingTimeInterval(1)
        let pack = MCPContextPack(
            name: "Selected", clipIDs: [reviewed.id],
            clipRevisions: [reviewed.id.uuidString: reviewed.contextRevision])

        #expect(pack.contains(item: reviewed, boardIDs: [], now: now))
        #expect(!pack.contains(item: edited, boardIDs: [], now: now))
        #expect(!pack.contains(item: editedInPlace, boardIDs: [], now: now))

        let legacyJSON = Data(
            #"{"name":"Old","clipIDs":["\#(reviewed.id.uuidString)"],"timeScope":"all-time"}"#.utf8)
        let legacy = try JSONDecoder().decode(MCPContextPack.self, from: legacyJSON)
        #expect(legacy.clipRevisions == nil)
        #expect(legacy.contains(item: edited, boardIDs: [], now: now))
    }

    @Test("client labels are bounded before entering UI or the ledger")
    func safeClientName() {
        let whitespace = MCPClientGrant(clientName: "   ")
        let oversized = MCPClientGrant(clientName: String(repeating: "x", count: 200))
        let multiline = MCPClientGrant(clientName: "  Cursor\nremote\t\u{001B}client  ")

        #expect(!whitespace.safeClientName.isEmpty)
        #expect(oversized.safeClientName.count == MCPClientGrant.maximumClientNameLength)
        #expect(multiline.safeClientName == "Cursor remote client")
    }
}
