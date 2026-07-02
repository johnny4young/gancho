import Foundation
import GRDB
import Testing

@testable import GanchoKit

/// In-memory database + throwaway blob directory per test (the same fixture
/// shape `GRDBClipboardStoreTests` uses).
private func makeStore() throws -> (GRDBClipboardStore, URL) {
    let blobDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("client-contract-tests-\(UUID().uuidString)", isDirectory: true)
    let store = GRDBClipboardStore(
        writer: try DatabaseQueue(), blobs: BlobStore(directory: blobDir))
    try store.migrate()
    return (store, blobDir)
}

@Suite("Client contract — facet conformances")
struct ClientContractTests {

    /// The bindings ARE the test: each line fails to COMPILE if the
    /// retroactive conformance in `ClientContract.swift` regresses (a facet
    /// requirement drifting from the store's real signature breaks here
    /// first, before any app target).
    @Test("GRDBClipboardStore binds to every facet existential")
    func facetBindings() throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let reading: any ClipReading = store
        let searching: any ClipSearching = store
        let mutator: any ClipMutating = store
        let enriching: any ClipEnriching = store
        let boards: any BoardStoring = store
        let snippets: any SnippetStoring = store
        let stats: any StoreStatsProviding = store
        let exporting: any ExportProviding = store
        let maintaining: any StoreMaintaining = store
        _ = (reading, searching, mutator, enriching, boards)
        _ = (snippets, stats, exporting, maintaining)

        // The composed contracts bind too: the third-party client surface and
        // the full first-party surface the app models will hold (refactor
        // plan step — replaces the `store as? GRDBClipboardStore` casts).
        let client: any GanchoClientStore = store
        let full: any FullClipStore = store
        _ = (client, full)
    }

    /// Dynamic dispatch through the facets reaches the same store: write via
    /// `ClipMutating`, observe via `ClipReading`/`StoreStatsProviding` — a
    /// cheap runtime smoke over the conformances, not a storage test
    /// (`GRDBClipboardStoreTests` owns those).
    @Test("Facets dispatch to the shared store")
    func facetRoundTrip() async throws {
        let (store, dir) = try makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let mutator: any ClipMutating = store
        let reading: any ClipReading = store
        let stats: any StoreStatsProviding = store

        let item = ClipItem(
            title: "contract", preview: "hello",
            contentHash: ClipItem.hash(of: "hello", kind: .text))
        try await mutator.insert(item, content: .text("hello"))

        #expect(try await reading.count() == 1)
        #expect(try await reading.item(id: item.id)?.preview == "hello")
        #expect(try await reading.content(for: item.id) == .text("hello"))

        try await mutator.setPinned(id: item.id, true)
        #expect(try await stats.pinnedCount() == 1)

        try await mutator.delete(id: item.id)
        #expect(try await reading.count() == 0)
    }
}
