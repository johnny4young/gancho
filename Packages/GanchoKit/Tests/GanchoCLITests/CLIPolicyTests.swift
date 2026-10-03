import Foundation
import GanchoKit
import Testing

@testable import gancho

@Suite("gancho CLI — privacy decisions")
struct CLIPolicyTests {
    @Test("save refuses detected secrets unless --allow-secret is given")
    func saveRefusesSecrets() {
        // Split so the synthetic fixture is not a contiguous credential in source.
        let secret = "db pass" + "word: hunter2-is-bad"
        let refusal = CLIPolicy.saveRefusal(for: secret, allowSecret: false)
        #expect(refusal != nil)
        #expect(refusal?.contains("hunter2") == false, "the refusal must stay content-free")
        #expect(CLIPolicy.saveRefusal(for: secret, allowSecret: true) == nil)
        #expect(CLIPolicy.saveRefusal(for: "func greet() {}", allowSecret: false) == nil)
    }

    @Test("copy refuses sensitive clips unless --reveal and leaves expiry to the store")
    func copyRefusals() {
        let now = Date(timeIntervalSince1970: 1_000)
        let plain = ClipItem(preview: "plain", contentHash: "p")
        let sensitive = ClipItem(
            kind: .secret, preview: "••••", contentHash: "s", isSensitive: true,
            expiresAt: now.addingTimeInterval(60))
        // Retention keeps a pinned, non-sensitive clip past its expiry date.
        let keptPastExpiry = ClipItem(
            preview: "kept", contentHash: "k", isPinned: true,
            expiresAt: now.addingTimeInterval(-1))

        #expect(CLIPolicy.copyRefusal(for: plain, reveal: false) == nil)
        #expect(CLIPolicy.copyRefusal(for: sensitive, reveal: false) != nil)
        #expect(CLIPolicy.copyRefusal(for: sensitive, reveal: true) == nil)
        #expect(CLIPolicy.copyRefusal(for: keptPastExpiry, reveal: false) == nil)
    }

    @Test("copy marks its own write and conceals sensitive content")
    func pasteboardMarkers() {
        let plain = ClipItem(preview: "plain", contentHash: "p")
        let sensitive = ClipItem(kind: .secret, contentHash: "s", isSensitive: true)

        let plainMarkers = CLIPolicy.pasteboardMarkers(for: plain)
        #expect(plainMarkers == ["com.johnny4young.gancho.self-write"])
        #expect(
            CLIPolicy.pasteboardMarkers(for: sensitive)
                == plainMarkers + ["org.nspasteboard.ConcealedType"])
    }

    @Test("export --out writes an owner-only file, also over an existing one")
    func exportIsOwnerOnly() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-export-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        try CLIPolicy.writePrivately(Data("{}".utf8), to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try Data(contentsOf: url) == Data("{}".utf8))
    }
}
