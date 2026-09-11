import CloudKit
import Foundation
import GanchoKit
import Synchronization
import Testing

@testable import GanchoSync

@Suite("SyncPollTokens persistence and recovery")
struct SyncPollTokensTests {
    private struct State: Sendable {
        var data: Data?
        var saveCount = 0
    }

    private final class MemoryState: Sendable {
        private let state: Mutex<State>

        init(seed: Data? = nil) { state = Mutex(State(data: seed)) }

        var saveCount: Int { state.withLock { $0.saveCount } }

        var store: SyncStateStore {
            SyncStateStore(
                load: { [self] in state.withLock { $0.data } },
                save: { [self] value in
                    state.withLock {
                        $0.data = value
                        $0.saveCount += 1
                    }
                })
        }
    }

    @Test("No file yet means poll from the beginning, not a crash")
    func absentFileLoadsEmpty() {
        #expect(SyncPollTokens.load(from: MemoryState().store) == SyncPollTokens())
    }

    @Test("No store at all is the same as no file")
    func nilStoreLoadsEmpty() {
        #expect(SyncPollTokens.load(from: nil) == SyncPollTokens())
        SyncPollTokens(database: Data([1])).save(to: nil)  // must not trap
    }

    @Test("Damaged bytes re-scan instead of throwing")
    func damagedFileLoadsEmpty() {
        for damaged in [Data("not a plist".utf8), Data([0x00, 0xFF, 0x00]), Data()] {
            let state = MemoryState(seed: damaged)
            #expect(
                SyncPollTokens.load(from: state.store) == SyncPollTokens(),
                "\(damaged.count) damaged bytes must degrade, not decode")
        }
    }

    @Test("A well-formed plist of the wrong shape also re-scans")
    func foreignPlistLoadsEmpty() throws {
        // The engine's own state blob living at this path by mistake is the
        // realistic version of this: valid plist, wrong contents.
        let foreign = try PropertyListEncoder().encode(["unrelated": "value"])
        #expect(SyncPollTokens.load(from: MemoryState(seed: foreign).store) == SyncPollTokens())
    }

    @Test("A missing database token decodes; a missing zones map does not")
    func partialShapesAreTreatedDifferentlyOnPurpose() throws {
        // Pins the distinction the doc comment draws, because the two look
        // alike and behave oppositely. `database == nil` is the legitimate
        // pre-first-poll state, so it must survive a round trip. `zones` is
        // required, so a file without it is damage and the whole file goes.
        let noDatabase = try PropertyListSerialization.data(
            fromPropertyList: ["zones": ["clips": Data([1])]], format: .xml, options: 0)
        let loaded = SyncPollTokens.load(from: MemoryState(seed: noDatabase).store)
        #expect(loaded == SyncPollTokens(zones: ["clips": Data([1])]))

        let noZones = try PropertyListSerialization.data(
            fromPropertyList: ["database": Data([9])], format: .xml, options: 0)
        #expect(SyncPollTokens.load(from: MemoryState(seed: noZones).store) == SyncPollTokens())
    }

    @Test("What was saved is what comes back")
    func roundTripsThroughTheStore() {
        let state = MemoryState()
        let tokens = SyncPollTokens(
            database: Data([0xDE, 0xAD]),
            zones: ["clips": Data([0x01]), "boards": Data([0x02])])
        tokens.save(to: state.store)

        #expect(state.saveCount == 1)
        #expect(SyncPollTokens.load(from: state.store) == tokens)
    }

    @Test("Resetting to empty is persisted, not skipped")
    func emptyTokensOverwriteTheFile() {
        // The expired-token path saves EMPTY tokens to force a full re-scan.
        // Treating that as "nothing to write" would leave the stale file in
        // place and re-scan nothing.
        let state = MemoryState()
        SyncPollTokens(database: Data([0xAA]), zones: ["clips": Data([0x01])]).save(to: state.store)
        SyncPollTokens().save(to: state.store)

        #expect(state.saveCount == 2)
        #expect(SyncPollTokens.load(from: state.store) == SyncPollTokens())
    }

    @Test("An absent or damaged archive is a nil token, never a trap")
    func unarchiveDegradesQuietly() {
        #expect(SyncPollTokens.unarchive(nil) == nil)
        #expect(SyncPollTokens.unarchive(Data()) == nil)
        #expect(SyncPollTokens.unarchive(Data("still not an archive".utf8)) == nil)
    }

    @Test("A secure archive of an unexpected class is rejected")
    func unexpectedArchiveClassIsRejected() throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: NSString(string: "not a change token"), requiringSecureCoding: true)
        #expect(SyncPollTokens.unarchive(data) == nil)
    }

    @Test("The adapter's existing property-list format remains compatible")
    func existingFormatRemainsCompatible() throws {
        let legacy: [String: Any] = [
            "database": Data([1]),
            "zones": ["ClipsZone": Data([2]), "BoardsZone": Data([3])]
        ]
        for format in [PropertyListSerialization.PropertyListFormat.binary, .xml] {
            let bytes = try PropertyListSerialization.data(
                fromPropertyList: legacy, format: format, options: 0)
            let state = MemoryState(seed: bytes)
            let loaded = SyncPollTokens.load(from: state.store)
            #expect(loaded.database == Data([1]))
            #expect(loaded.zones == ["ClipsZone": Data([2]), "BoardsZone": Data([3])])
            loaded.save(to: state.store)
            let saved = try #require(state.store.load())
            let decoded =
                try PropertyListSerialization.propertyList(
                    from: saved, options: [], format: nil) as? NSDictionary
            #expect(decoded == legacy as NSDictionary)
        }
    }

    @Test("Concurrent store callbacks preserve complete writes and save counts")
    func concurrentStoreCallbacks() async {
        let state = MemoryState()
        let tokens = SyncPollTokens(database: Data([1]), zones: ["ClipsZone": Data([2])])
        tokens.save(to: state.store)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    tokens.save(to: state.store)
                    #expect(SyncPollTokens.load(from: state.store) == tokens)
                }
            }
        }
        #expect(state.saveCount == 101)
    }
}
