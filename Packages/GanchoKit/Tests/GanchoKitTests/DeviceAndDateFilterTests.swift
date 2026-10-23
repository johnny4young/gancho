import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Search filters — device and created-before")
struct DeviceAndDateFilterTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("device-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    private let cutoff = Date(timeIntervalSince1970: 1_700_000_000)

    private func seed(_ store: GRDBClipboardStore) async throws -> (old: ClipItem, new: ClipItem) {
        let old = ClipItem(
            createdAt: cutoff.addingTimeInterval(-60), preview: "invoice mac",
            contentHash: "o", sourceDeviceName: "MacBook Pro")
        let new = ClipItem(
            createdAt: cutoff, preview: "invoice phone", contentHash: "n",
            sourceDeviceName: "iPhone")
        for item in [old, new] { try await store.insert(item, content: .text(item.preview)) }
        return (old, new)
    }

    @Test("device: keeps only clips copied on that device, in every mode")
    func deviceFilter() async throws {
        let store = try makeStore()
        let (old, _) = try await seed(store)
        for mode in ClipSearchQuery.Mode.allCases {
            let hits = try await store.search(
                ClipSearchQuery(text: "invoice", mode: mode, deviceName: "MacBook Pro"), limit: 10)
            #expect(hits.map(\.id) == [old.id], "\(mode)")
        }
        let none = try await store.search(
            ClipSearchQuery(text: "", deviceName: "iPad"), limit: 10)
        #expect(none.isEmpty)
        let tokenOnly = try await store.search(
            ClipSearchQuery(text: "", deviceName: "MacBook Pro"), limit: 10)
        #expect(tokenOnly.map(\.id) == [old.id], "a token alone filters an empty field")
        let dateOnly = try await store.search(
            ClipSearchQuery(text: "", createdBefore: cutoff), limit: 10)
        #expect(dateOnly.map(\.id) == [old.id])
    }

    @Test("Device names list each device once, newest first")
    func deviceNames() async throws {
        let store = try makeStore()
        _ = try await seed(store)
        #expect(try await store.deviceNames(limit: 8) == ["iPhone", "MacBook Pro"])
        #expect(try await store.deviceNames(limit: 0).isEmpty)
    }

    @Test("before: is strict, so a clip at the cutoff is left out")
    func createdBefore() async throws {
        let store = try makeStore()
        let (old, _) = try await seed(store)
        let hits = try await store.search(
            ClipSearchQuery(text: "invoice", createdBefore: cutoff), limit: 10)
        #expect(hits.map(\.id) == [old.id])
    }

    @Test("A saved filter keeps its device and date, and the in-memory match agrees")
    func savedRuleRoundTrip() async throws {
        let store = try makeStore()
        let (old, new) = try await seed(store)
        let rule = SmartCollectionRule(
            name: "Mac before", textContains: "invoice", deviceName: "MacBook Pro",
            createdBefore: cutoff)
        let decoded = try JSONDecoder().decode(
            SmartCollectionRule.self, from: JSONEncoder().encode(rule))
        #expect(decoded == rule)
        #expect(try await store.search(decoded.query, limit: 10).map(\.id) == [old.id])
        #expect(rule.matches(old))
        #expect(!rule.matches(new))
    }

    @Test("A rule saved before these filters existed still decodes")
    func legacyRuleDecodes() throws {
        let legacy = Data(#"{"id":"\#(UUID().uuidString)","name":"Old","pinnedOnly":false}"#.utf8)
        let rule = try JSONDecoder().decode(SmartCollectionRule.self, from: legacy)
        #expect(rule.deviceName == nil)
        #expect(rule.createdBefore == nil)
    }
}
