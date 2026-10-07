import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Content-bound generated titles")
struct ContentBoundTitleTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("title-body-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test func changedBodyRejectsTitleWithoutQueueingAnotherUpload() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "old", contentHash: "title-race")
        try await store.insert(item, content: .text("old"))
        try await store.updateClipText(id: item.id, text: "edited")
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        let before = try #require(try await store.item(id: item.id))

        #expect(
            !(try await store.updateTitleIfEmptyAndCurrent(
                id: item.id, title: "Old topic", expectedText: "old")))
        #expect(try await store.item(id: item.id) == before)
        #expect(try await store.pendingUploadIDs().isEmpty)
        #expect(
            try await store.updateTitleIfEmptyAndCurrent(
                id: item.id, title: "Current topic", expectedText: "edited"))
        #expect(try await store.item(id: item.id)?.title == "Current topic")
        #expect(try await store.pendingUploadIDs() == [item.id])
    }

    @Test func manualTitleStillWinsEvenWithAnIdenticalBody() async throws {
        let store = try makeStore()
        let item = ClipItem(title: "Manual", preview: "body", contentHash: "manual-race")
        try await store.insert(item, content: .text("body"))
        #expect(
            !(try await store.updateTitleIfEmptyAndCurrent(
                id: item.id, title: "Generated", expectedText: "body")))
        #expect(try await store.item(id: item.id)?.title == "Manual")
    }

    @Test func missingAndRecreatedRowsRequireMatchingCurrentBody() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "old", contentHash: "recreated-title")
        #expect(
            !(try await store.updateTitleIfEmptyAndCurrent(
                id: item.id, title: "Old", expectedText: "old")))
        try await store.insert(item, content: .text("new"))
        #expect(
            !(try await store.updateTitleIfEmptyAndCurrent(
                id: item.id, title: "Old", expectedText: "old")))
        try await store.delete(id: item.id)
        try await store.insert(item, content: .text("old"))
        #expect(
            try await store.updateTitleIfEmptyAndCurrent(
                id: item.id, title: "Same topic", expectedText: "old"))
    }

    @Test func changedEligibilityRejectsAnIdenticalBody() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "body", contentHash: "title-eligibility")
        try await store.insert(item, content: .text("body"))
        let mutations = [
            "isSensitive = 1", "kind = 'jwt'", "kind = 'future-kind'", "isArchived = 1",
            "expiresAt = '2000-01-01 00:00:00.000'", "contentTypeIdentifier = 'public.file-url'"
        ]
        for mutation in mutations {
            try await store.writer.write { db in
                try db.execute(
                    sql: """
                        UPDATE clip SET isSensitive = 0, kind = 'text', isArchived = 0,
                            expiresAt = NULL, contentTypeIdentifier = NULL WHERE id = ?
                        """,
                    arguments: [item.id.uuidString])
                try db.execute(
                    sql: "UPDATE clip SET \(mutation) WHERE id = ?",
                    arguments: [item.id.uuidString])
            }
            #expect(
                !(try await store.updateTitleIfEmptyAndCurrent(
                    id: item.id, title: "Generated", expectedText: "body")),
                "Accepted changed eligibility: \(mutation)")
        }
    }
}
