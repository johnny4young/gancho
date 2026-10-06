import Foundation
import GRDB
import Testing

@testable import GanchoKit

// A stored weak reference works on the package's Swift 6.2 minimum too;
// unlike a weak local, it does not trigger newer compiler mutability warnings.
private final class WeakGenerationFacade {
    weak var value: GRDBClipboardStore?
    init(_ value: GRDBClipboardStore?) { self.value = value }
}

@Suite("Generation pins follow actual SQLite connection lifetime")
struct StoreGenerationConnectionPinTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test("Retained writer blocks recovery; closed writer/configuration does not over-pin")
    func writerConnectionLifetime() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var store: GRDBClipboardStore? = try GRDBClipboardStore(directory: root)
        let facade = WeakGenerationFacade(store)
        let writer = try #require(store?.writer)
        let configuration = writer.configuration
        store = nil
        #expect(facade.value == nil)
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreGenerationRecovery.archive(in: root, suffix: "blocked")
        }
        try writer.close()
        try withExtendedLifetime(writer) {
            // Keep both writer and its configuration alive. The actual connection
            // has closed, so configuration/watchdog retention must not hold a pin.
            try StoreGenerationRecovery.archive(in: root, suffix: "closed")
            let preserved = root.appendingPathComponent(".unreadable-closed/gancho.sqlite")
            #expect(FileManager.default.fileExists(atPath: preserved.path))
            let forbidden = root.appendingPathComponent("unpinned.sqlite")
            #expect(throws: StoreGenerationLease.ConnectionFailure.self) {
                try DatabaseQueue(path: forbidden.path, configuration: configuration)
            }
        }
    }

    @Test("Independent snapshot stays pinned after its originating pool closes")
    func snapshotConnectionLifetime() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var store: GRDBClipboardStore? = try GRDBClipboardStore(directory: root)
        let facade = WeakGenerationFacade(store)
        let pool = try #require(store?.writer as? DatabasePool)
        let snapshot = try pool.makeSnapshot()
        store = nil
        #expect(facade.value == nil)
        try pool.close()
        #expect(throws: StoreProcessOwnership.Failure.self) {
            try StoreGenerationRecovery.archive(in: root, suffix: "blocked")
        }
        try snapshot.close()
        try StoreGenerationRecovery.archive(in: root, suffix: "snapshot-closed")
        let preserved = root.appendingPathComponent(".unreadable-snapshot-closed/gancho.sqlite")
        #expect(FileManager.default.fileExists(atPath: preserved.path))
    }
}
