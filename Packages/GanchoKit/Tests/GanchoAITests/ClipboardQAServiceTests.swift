import Testing

@testable import GanchoAI

/// The on-device answer is device-gated + non-deterministic, so the suite pins
/// the PURE contract: instructions that keep it grounded + secret-safe, and the
/// numbered prompt the retrieval feeds the model.
@Suite("Ask your clipboard — grounded QA")
struct ClipboardQAServiceTests {
    @Test("Instructions ground the answer in context, admit gaps, and guard secrets")
    func instructions() {
        let instructions = ClipboardQAService.instructions
        #expect(instructions.localizedCaseInsensitiveContains("only"))
        #expect(instructions.localizedCaseInsensitiveContains("secret"))
        // Told to admit when the answer isn't present rather than hallucinate.
        #expect(instructions.localizedCaseInsensitiveContains("couldn"))
    }

    @Test("Prompt numbers each source and ends with the question")
    func promptBuilds() {
        let prompt = ClipboardQAService.prompt(
            question: "what is the address?",
            sources: ["Calle Falsa 123", "user@example.com"])
        #expect(prompt.contains("[1] Calle Falsa 123"))
        #expect(prompt.contains("[2] user@example.com"))
        #expect(prompt.contains("Question: what is the address?"))
    }
}
