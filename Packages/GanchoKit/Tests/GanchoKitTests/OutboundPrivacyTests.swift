import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Outbound privacy — intrinsic kinds and explicit export consent")
struct OutboundPrivacyTests {
    @Test("Keyboard filters precede SQL limits in both browse and search")
    func keyboardQueryDoesNotStarveSafeRows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "keyboard-query-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: root))
        try store.migrate()
        let safe = ClipItem(
            createdAt: .distantPast, preview: "synthetic match", contentHash: "safe")
        try await store.insert(safe, content: .text("synthetic match"))
        for index in 0..<65 {
            let kind: ClipContentKind = index.isMultiple(of: 2) ? .jwt : .text
            try await store.insert(
                ClipItem(
                    kind: kind, preview: "synthetic match", contentHash: "hidden-\(index)",
                    isSensitive: kind == .text), content: .text("synthetic match"))
        }
        for text in ["", "synthetic"] {
            let result = try await store.search(KeyboardClips.query(text: text), limit: 1)
            #expect(result.map(\.id) == [safe.id])
        }
    }

    @Test(arguments: [ClipContentKind.jwt, .creditCard, .secret, .text])
    func excludedFromKeyboard(kind: ClipContentKind) {
        let protected = ClipItem(kind: kind, isSensitive: kind == .text)
        let safe = ClipItem(kind: .text, preview: "synthetic-safe")
        let entries = KeyboardClips.ordered(
            pinned: [protected], recent: [protected, safe], recentLimit: 1)
        #expect(entries.map(\.id) == [safe.id])
    }

    @Test("Expired clips never reach the keyboard list")
    func expiredExcludedFromKeyboard() {
        let expired = ClipItem(preview: "synthetic-expired", expiresAt: .now - 1)
        let safe = ClipItem(preview: "synthetic-safe")
        let entries = KeyboardClips.ordered(pinned: [expired], recent: [expired, safe])
        #expect(entries.map(\.id) == [safe.id])
    }

    @Test(arguments: [ClipContentKind.jwt, .creditCard, .secret, .text])
    func excludedFromEveryExportUnlessExplicitlyIncluded(kind: ClipContentKind) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbound-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: root.appendingPathComponent("blobs")))
        try store.migrate()
        let marker = "synthetic-protected-export"
        try await store.insert(
            ClipItem(
                kind: kind, preview: marker, contentHash: "protected", isSensitive: kind == .text),
            content: .text(marker))
        try await store.insert(
            ClipItem(preview: "synthetic-safe", contentHash: "safe"),
            content: .text("synthetic-safe"))

        for exclude in [true, false] {
            let json = try #require(
                String(
                    bytes: try await store.exportJSON(excludeSensitive: exclude), encoding: .utf8))
            let csv = try #require(
                String(
                    bytes: try await store.exportCSV(excludeSensitive: exclude), encoding: .utf8))
            let archive = root.appendingPathComponent("archive-\(exclude)")
            let manifest = try await GanchoArchive.export(
                from: store, to: archive, options: .init(excludeSensitive: exclude))
            let archived = try #require(
                String(
                    bytes: try Data(contentsOf: archive.appendingPathComponent("clips.json")),
                    encoding: .utf8))
            for output in [json, csv, archived] {
                #expect(output.contains(marker) == !exclude)
                #expect(output.contains("synthetic-safe"))
            }
            #expect(manifest.clipCount == (exclude ? 1 : 2))
        }
    }
}
