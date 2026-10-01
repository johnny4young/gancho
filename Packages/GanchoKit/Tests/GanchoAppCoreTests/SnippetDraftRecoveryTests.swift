import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Classified snippet recovery")
struct SnippetDraftRecoveryTests {
    @Test("Recovery classifies and normalizes like capture, with fresh identities")
    func classification() throws {
        let fields = SnippetDraft.Fields(
            title: "Link", keyword: "link", body: "https://example.com/?utm_source=test")
        let first = try SnippetDraftRecovery.prepare(
            fields, sensitiveLifetime: 600, detectSecrets: true, fallbackTitle: "Recovered")
        let second = try SnippetDraftRecovery.prepare(
            fields, sensitiveLifetime: 600, detectSecrets: true, fallbackTitle: "Recovered")
        #expect(first.item.kind == .url)
        #expect(first.item.id != second.item.id)
        #expect(!first.text.contains("utm_source"))
        #expect(first.item.title == fields.title)
    }

    @Test("Protected content is rejected before persistence")
    func protectedContent() {
        #expect(throws: SnippetDraftSaveError.protectedContent) {
            try SnippetDraftRecovery.prepare(
                .init(body: "4111 1111 1111 1111"), sensitiveLifetime: 600,
                detectSecrets: true, fallbackTitle: "Recovered")
        }
    }

    @Test("A blank title takes the caller's localized fallback")
    func fallbackTitle() throws {
        let prepared = try SnippetDraftRecovery.prepare(
            .init(title: "  ", body: "Hello"), sensitiveLifetime: 600,
            detectSecrets: false, fallbackTitle: "Recovered")
        #expect(prepared.item.title == "Recovered")
        #expect(prepared.text == "Hello")
    }
}
