import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Word diff and saved change prompts")
struct WordDiffTests {
    private func side(
        _ segments: [WordDiff.Segment], dropping kind: WordDiff.Kind
    ) -> String {
        segments.filter { $0.kind != kind }.map(\.text).joined()
    }

    @Test("Each side rebuilds exactly and changed words are marked")
    func rebuildsBothSides() {
        let old = "Today: improve editing\nBlockers: none"
        let new = "Today: ship editing\nBlockers: none"
        let segments = WordDiff.diff(old, new)

        #expect(side(segments, dropping: .added) == old)
        #expect(side(segments, dropping: .removed) == new)
        #expect(segments.contains(WordDiff.Segment(kind: .removed, text: "improve ")))
        #expect(segments.contains(WordDiff.Segment(kind: .added, text: "ship ")))
    }

    @Test("Identical texts are one unchanged segment; empty sides work")
    func edges() {
        #expect(WordDiff.diff("same text", "same text") == [.init(kind: .same, text: "same text")])
        #expect(WordDiff.diff("", "new") == [.init(kind: .added, text: "new")])
        #expect(WordDiff.diff("old", "") == [.init(kind: .removed, text: "old")])
    }

    @Test("Very long texts fall back to a whole replacement")
    func longFallback() {
        let old = Array(repeating: "a", count: WordDiff.maximumTokens + 1).joined(separator: " ")
        let segments = WordDiff.diff(old, "b")
        #expect(segments == [.init(kind: .removed, text: old), .init(kind: .added, text: "b")])
    }

    @Test("Saved prompts are trimmed, deduplicated newest first and capped")
    func savedPrompts() throws {
        var saved = SavedPrompts()
        saved.add("  make it formal ")
        saved.add("shorter")
        saved.add("Make it formal")
        saved.add("   ")
        #expect(saved.prompts == ["Make it formal", "shorter"])
        for index in 0..<20 { saved.add("prompt \(index)") }
        #expect(saved.prompts.count == SavedPrompts.maximumCount)

        let defaults = try #require(UserDefaults(suiteName: "prompts-\(UUID().uuidString)"))
        saved.save(to: defaults)
        #expect(SavedPrompts.load(from: defaults) == saved)
        saved.remove("prompt 19")
        #expect(!saved.prompts.contains("prompt 19"))
    }

    @Test("A prompt that holds a secret or runs past the limit is not kept")
    func savedPromptsRefuseSecretsAndLongText() {
        var saved = SavedPrompts()
        let secret = saved.add("use key AKIAIOSFODNN7EXAMPLE")
        let long = saved.add(String(repeating: "a", count: SavedPrompts.maximumLength + 1))
        let plain = saved.add("make it shorter")
        #expect(!secret && !long && plain)
        #expect(saved.prompts == ["make it shorter"])
    }
}
