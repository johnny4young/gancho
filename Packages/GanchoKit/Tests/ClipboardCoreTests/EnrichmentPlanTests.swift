import Foundation
import GanchoKit
import Testing

@testable import ClipboardCore

@Suite("Enrichment plan — the shared capture-time gating policy")
struct EnrichmentPlanTests {
    private let allOn = IntelligencePreferences()

    // MARK: - Tier and sensitivity vetoes (ahead of any toggle)

    @Test("Free tier plans nothing, even with every toggle on")
    func freeTierPlansNothing() {
        let plan = EnrichmentPlan(
            content: .text(hasTitle: false), isSensitive: false, isPro: false, preferences: allOn)
        #expect(plan.isEmpty)
    }

    @Test("A sensitive clip is never enriched, even on Pro with every toggle on")
    func sensitiveClipPlansNothing() {
        let text = EnrichmentPlan(
            content: .text(hasTitle: false), isSensitive: true, isPro: true, preferences: allOn)
        let image = EnrichmentPlan(
            content: .image, isSensitive: true, isPro: true, preferences: allOn)
        #expect(text.isEmpty)
        #expect(image.isEmpty)
    }

    // MARK: - Text clips

    @Test("Pro text, no title, all on → titles + embedding")
    func proTextAllOn() {
        let plan = EnrichmentPlan(
            content: .text(hasTitle: false), isSensitive: false, isPro: true, preferences: allOn)
        #expect(plan.stages == [.title, .embedding])
        #expect(plan.runs(.title))
        #expect(plan.runs(.embedding))
        #expect(!plan.runs(.ocr))
    }

    @Test("An existing title skips the title stage but still embeds")
    func textWithTitleSkipsTitle() {
        let plan = EnrichmentPlan(
            content: .text(hasTitle: true), isSensitive: false, isPro: true, preferences: allOn)
        #expect(plan.stages == [.embedding])
    }

    @Test("Titles off removes only the title stage")
    func titlesOff() {
        var prefs = allOn
        prefs.intelligentTitles = false
        let plan = EnrichmentPlan(
            content: .text(hasTitle: false), isSensitive: false, isPro: true, preferences: prefs)
        #expect(plan.stages == [.embedding])
    }

    @Test("Semantic search off removes only the embedding stage")
    func semanticOff() {
        var prefs = allOn
        prefs.semanticSearch = false
        let plan = EnrichmentPlan(
            content: .text(hasTitle: false), isSensitive: false, isPro: true, preferences: prefs)
        #expect(plan.stages == [.title])
    }

    // MARK: - Image clips

    @Test("Pro image with searchable screenshots on → OCR only")
    func proImageOCR() {
        let plan = EnrichmentPlan(
            content: .image, isSensitive: false, isPro: true, preferences: allOn)
        #expect(plan.stages == [.ocr])
    }

    @Test("Searchable screenshots off → image plans nothing")
    func ocrOff() {
        var prefs = allOn
        prefs.searchableScreenshots = false
        let plan = EnrichmentPlan(
            content: .image, isSensitive: false, isPro: true, preferences: prefs)
        #expect(plan.isEmpty)
    }

    @Test("Payloads with no enrichable content plan nothing")
    func otherPlansNothing() {
        let plan = EnrichmentPlan(
            content: .other, isSensitive: false, isPro: true, preferences: allOn)
        #expect(plan.isEmpty)
    }

    // MARK: - Convenience: derive the category from a stored ClipContent + kind

    @Test("ClipContent convenience mirrors each pipeline's content switch")
    func convenienceFromClipContent() {
        // Image binary → OCR.
        let image = EnrichmentPlan(
            content: .binary(data: Data([0x1]), typeIdentifier: "public.png"), kind: .image,
            isSensitive: false, hasTitle: false, isPro: true, preferences: allOn)
        #expect(image.stages == [.ocr])

        // RTF binary (kind not image) → other → nothing.
        let rtf = EnrichmentPlan(
            content: .binary(data: Data([0x1]), typeIdentifier: "public.rtf"), kind: .richText,
            isSensitive: false, hasTitle: false, isPro: true, preferences: allOn)
        #expect(rtf.isEmpty)

        // Plain text → title + embedding.
        let text = EnrichmentPlan(
            content: .text("hello world"), kind: .text,
            isSensitive: false, hasTitle: false, isPro: true, preferences: allOn)
        #expect(text.stages == [.title, .embedding])

        // File references → other → nothing.
        let files = EnrichmentPlan(
            content: .fileReferences(["/tmp/a.txt"]), kind: .fileReference,
            isSensitive: false, hasTitle: false, isPro: true, preferences: allOn)
        #expect(files.isEmpty)

        // Missing content → other → nothing.
        let none = EnrichmentPlan(
            content: nil, kind: .text,
            isSensitive: false, hasTitle: false, isPro: true, preferences: allOn)
        #expect(none.isEmpty)
    }
}
