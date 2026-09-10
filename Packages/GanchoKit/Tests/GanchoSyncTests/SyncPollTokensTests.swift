import CloudKit
import Foundation
import GanchoKit
import Testing

@testable import GanchoSync

/// The explicit pull's change-token file, which had no coverage while it lived
/// inside the adapter: it ran only against a live CloudKit account.
///
/// What matters here is not the happy path but the DAMAGED ones. Every failure
/// must degrade to "re-scan from the beginning", because a poll that re-scans
/// costs one round trip while a poll that throws leaves the pull dead until the
/// next launch.
@Suite("SyncPollTokens — a damaged token file must cost a re-scan, not the pull")
struct SyncPollTokensTests {
    /// In-memory `SyncStateStore`. A final class over a lock because the store's
    /// closures are `@Sendable` and these assertions read back what a
    /// synchronous call wrote.
    private final class MemoryState: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?
        private(set) var saveCount = 0

        init(seed: Data? = nil) { data = seed }

        var store: SyncStateStore {
            SyncStateStore(
                load: { [self] in
                    lock.lock()
                    defer { lock.unlock() }
                    return data
                },
                save: { [self] value in
                    lock.lock()
                    defer { lock.unlock() }
                    data = value
                    saveCount += 1
                })
        }

        var stored: Data? {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    @Test("No file yet means poll from the beginning, not a crash")
    func absentFileLoadsEmpty() {
        #expect(SyncPollTokens.load(from: MemoryState().store) == SyncPollTokens())
    }

    @Test("No store at all is the same as no file")
    func nilStoreLoadsEmpty() {
        // The adapter is constructed without a poll store on every path that
        // never polls (free tier, signed out), so this is a live case and not
        // a defensive one.
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
        // `CKServerChangeToken` has no public initializer, so a test can never
        // hold a real one — which is precisely why the DAMAGED paths are the
        // ones worth pinning here.
        #expect(SyncPollTokens.unarchive(nil) == nil)
        #expect(SyncPollTokens.unarchive(Data()) == nil)
        #expect(SyncPollTokens.unarchive(Data("still not an archive".utf8)) == nil)
    }
}
