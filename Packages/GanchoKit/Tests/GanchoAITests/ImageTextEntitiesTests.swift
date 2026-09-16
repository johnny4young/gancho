import Foundation
import Testing

@testable import GanchoAI

@Suite("OCR entity chips — links, emails and the translation offer")
struct ImageTextEntitiesTests {
    @Test("Links and emails are found inside sentences, deduplicated and capped")
    func linksAndEmails() throws {
        let text = """
            Ver https://gancho.app/docs y otra vez https://gancho.app/docs (repetido).
            Escribe a soporte@gancho.app, visita http://example.com y https://apple.com/mac
            """
        let found = ImageTextEntityDetector().entities(in: text)
        #expect(found.count == ImageTextEntityDetector.limit, "got: \(found)")
        #expect(found[0] == .link(try #require(URL(string: "https://gancho.app/docs"))))
        guard case .email(let address, let url) = found[1] else {
            Issue.record("second entity should be the email, got \(found[1])")
            return
        }
        #expect(address == "soporte@gancho.app")
        #expect(url.scheme == "mailto")
        #expect(found[2] == .link(try #require(URL(string: "http://example.com"))))
    }

    @Test("A bare domain the detector recognizes gets a scheme so the chip can open it")
    func bareDomain() {
        // NSDataDetector is conservative with bare domains (newer TLDs such as
        // .app need the scheme); a classic host with a path is the case it owns.
        let found = ImageTextEntityDetector().entities(in: "Docs: www.example.com/docs/ocr")
        guard case .link(let url)? = found.first else {
            Issue.record("expected a link, got \(found)")
            return
        }
        #expect(url.host == "www.example.com")
        #expect(url.scheme == "http")
    }

    @Test("Only http, https and mailto ever become a chip")
    func unsafeSchemesAreDropped() throws {
        for raw in [
            "file:///etc/passwd", "javascript:alert(1)", "ftp://files.example.com/x", "x-app://open"
        ] {
            #expect(
                ImageTextEntityDetector.entity(for: try #require(URL(string: raw))) == nil,
                Comment(rawValue: raw))
        }
        #expect(ImageTextEntityDetector.entity(for: try #require(URL(string: "https://"))) == nil)
        let mail = try #require(URL(string: "mailto:ana@example.com?subject=Hola"))
        #expect(
            ImageTextEntityDetector.entity(for: mail)
                == .email(address: "ana@example.com", url: mail))
    }

    @Test("Text without entities yields no chips")
    func nothing() {
        #expect(ImageTextEntityDetector().entities(in: "Reunión de kickoff · martes 10:00").isEmpty)
        #expect(ImageTextEntityDetector().entities(in: "").isEmpty)
    }

    private func engines(source: String?, status: TranslationPairStatus) -> TranslationEngines {
        TranslationEngines(
            identifySource: { _ in source.map { Locale.Language(identifier: $0) } },
            pairStatus: { _, _ in status },
            native: { text, _, _ in text },
            languageModel: { text, _ in text })
    }

    @Test("Translate is offered only across languages and only when an engine can run")
    func translationOffer() async {
        let english = Locale.Language(identifier: "en")
        let text = "Texto en otro idioma"
        // Installed native pair, no model: native can run.
        #expect(
            await ImageTextTranslation.offer(
                for: text, interface: english, modelAvailable: false,
                engines: engines(source: "es", status: .installed)) == english)
        // Downloadable pair and no model: nothing can run now.
        #expect(
            await ImageTextTranslation.offer(
                for: text, interface: english, modelAvailable: false,
                engines: engines(source: "es", status: .downloadable)) == nil)
        // The model covers a missing pair.
        #expect(
            await ImageTextTranslation.offer(
                for: text, interface: english, modelAvailable: true,
                engines: engines(source: "es", status: .unsupported)) == english)
        // Same language, even across regions, is never offered.
        #expect(
            await ImageTextTranslation.offer(
                for: text, interface: Locale.Language(identifier: "es"), modelAvailable: true,
                engines: engines(source: "es-MX", status: .installed)) == nil)
        // Unknown source language: no offer rather than a guess.
        #expect(
            await ImageTextTranslation.offer(
                for: text, interface: english, modelAvailable: true,
                engines: engines(source: nil, status: .installed)) == nil)
    }
}
