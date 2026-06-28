import Foundation
import Testing

@testable import GanchoKit

/// The `isDurable` flag drives the "your history isn't being saved" banner when
/// the encrypted store can't open and the app falls back to memory. It's read
/// off `any ClipboardStore`, so the existential must dispatch to the override.
@Suite("Store durability flag")
struct ClipboardStoreDurabilityTests {
    @Test("The in-memory fallback reports itself as non-durable")
    func inMemoryIsEphemeral() {
        #expect(InMemoryClipboardStore().isDurable == false)
        let erased: any ClipboardStore = InMemoryClipboardStore()
        #expect(erased.isDurable == false, "existential dispatch must see the override")
    }

    @Test("A real GRDB store is durable")
    func grdbIsDurable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try GRDBClipboardStore(directory: dir)
        #expect(store.isDurable == true)
        let erased: any ClipboardStore = store
        #expect(erased.isDurable == true)
    }
}
