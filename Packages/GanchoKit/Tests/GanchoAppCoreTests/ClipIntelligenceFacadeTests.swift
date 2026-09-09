import Foundation
import GanchoAI
import GanchoKit
import Testing

@testable import GanchoAppCore

/// The facade's guards, which are the reason it exists: they used to be copied
/// into both shells, where no unit test could reach them at all.
///
/// Deliberately does NOT test the model-backed paths. Apple Intelligence is
/// unavailable on CI, so an assertion about a transform or an answer would pass
/// for the wrong reason — the guards below are the part that must hold whether
/// or not a model is present.
@Suite("ClipIntelligenceFacade — the guards both shells used to copy")
@MainActor
struct ClipIntelligenceFacadeTests {
    private func clip(sensitive: Bool = false) -> ClipItem {
        ClipItem(kind: .text, preview: "p", contentHash: "h", isSensitive: sensitive)
    }

    @Test("A sensitive clip gets no suggestion, through either guard")
    func sensitiveClipGetsNoSuggestion() async {
        // Honest about what this can prove: `BoardSuggestionService` refuses a
        // sensitive clip as ITS first line too, so no assertion here can tell
        // which of the two guards fired. The authoritative coverage is
        // `BoardSuggestionServiceTests`; this pins the composed result only, so
        // that removing the facade's redundant guard is caught if the
        // suggester's is ever relaxed.
        let store = FakeStore(boards: [Pinboard(name: "Work")])
        let suggestion = await ClipIntelligenceFacade().suggestedBoard(
            for: clip(sensitive: true), store: store, autoBoardEnabled: true)

        #expect(suggestion == nil)
    }

    @Test("The auto-board toggle is honored before anything is read")
    func toggleOffReadsNothing() async {
        let store = FakeStore(boards: [Pinboard(name: "Work")])
        let suggestion = await ClipIntelligenceFacade().suggestedBoard(
            for: clip(), store: store, autoBoardEnabled: false)

        #expect(suggestion == nil)
        #expect(await store.pinboardsCalls == 0, "the toggle was off and the store was read")
    }

    @Test("No durable store means no suggestion, not a crash")
    func noStoreSuggestsNothing() async {
        let suggestion = await ClipIntelligenceFacade().suggestedBoard(
            for: clip(), store: nil, autoBoardEnabled: true)
        #expect(suggestion == nil)
    }

    @Test("Asking without a durable store is unavailable, the same as no model")
    func askWithoutStoreIsUnavailable() async {
        // Both shells returned nil for this case by guarding their own store
        // handle first. Folding it into the facade keeps that answer identical
        // and puts it somewhere a test can see.
        let outcome = await ClipIntelligenceFacade().ask(
            "anything", store: nil, useSemantic: true)
        #expect(outcome == .unavailable)
    }

    @Test("Availability is read from the type that answers")
    func availabilityComesFromTheAnswerer() {
        // macOS used to read `ClipboardQAService` while answering through
        // `ClipboardQA`. They agree only because one forwards to the other —
        // this pins the facade to the answering type so a future condition on
        // either side cannot make "can I ask?" and "who answers?" disagree.
        #expect(ClipIntelligenceFacade.askAvailable == ClipboardQA.isAvailable)
    }
}
