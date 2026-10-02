import Foundation
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

#if SQLITE_HAS_CODEC
    @Suite("Plaintext-to-encrypted swap recovers from an interrupted launch")
    struct EncryptionSwapRecoveryTests {
        @Test("A finished export left without its plaintext original is published on launch")
        func leftoverExportIsRecovered() async throws {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("gancho-swap-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let path = dir.appendingPathComponent("gancho.sqlite").path
            let key = try KeychainPassphraseStore.generateKey()

            var plaintext: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: nil)
            let item = ClipItem(preview: "survivor", contentHash: "survivor")
            try await plaintext?.insert(item, content: .text("survivor"))
            plaintext = nil
            // The state an older build left when it stopped between removing
            // the plaintext file and moving the export into place.
            try GRDBClipboardStore.encryptPlaintextStoreIfNeeded(at: path, passphrase: key)
            try FileManager.default.moveItem(atPath: path, toPath: path + ".encrypting")

            let reopened = try GRDBClipboardStore(directory: dir, passphrase: key)

            #expect(try await reopened.content(for: item.id) == .text("survivor"))
            #expect(!FileManager.default.fileExists(atPath: path + ".encrypting"))
        }
    }
#endif
