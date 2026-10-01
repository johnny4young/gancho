import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private struct RecipeDeliveryReader: ClipReading {
    var item = ClipItem(contentHash: "synthetic-recipe")
    let beforeContent: @Sendable () async -> Void
    var content = "Reviewed synthetic text"
    func items(ids: [UUID]) async throws -> [ClipItem] { ids.contains(item.id) ? [item] : [] }
    func item(id: UUID) async throws -> ClipItem? { id == item.id ? item : nil }
    func content(for id: UUID) async throws -> ClipContent? {
        await beforeContent()
        return id == item.id ? .text(content) : nil
    }
    func items(offset: Int, limit: Int) async throws -> [ClipItem] { [item] }
    func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] { [item] }
    func count() async throws -> Int { 1 }
    func thumbnailData(for id: UUID) async throws -> Data? { nil }
}
@MainActor private final class RecipeClipboardProbe {
    var unchanged = true
    var allowed = true
    var writes: [String] = []
}
@Suite("Reviewed recipe delivery") @MainActor
struct TextRecipeDeliveryTests {
    private enum Race: Sendable { case clipboard, privacy, cancellation }
    @Test func stableInputCopiesOnlyExplicitReviewedResult() async throws {
        let reader = RecipeDeliveryReader(beforeContent: {})
        let probe = RecipeClipboardProbe()
        #expect(try await perform(reader, probe) == .copied)
        #expect(probe.writes == ["Processed synthetic text"])
    }
    @Test(arguments: [Race.clipboard, .privacy, .cancellation])
    private func changesDuringReadNeverWrite(_ race: Race) async throws {
        let probe = RecipeClipboardProbe()
        let reader = RecipeDeliveryReader(beforeContent: {
            switch race {
            case .clipboard: await MainActor.run { probe.unchanged = false }
            case .privacy: await MainActor.run { probe.allowed = false }
            case .cancellation: withUnsafeCurrentTask { $0?.cancel() }
            }
        })
        let task = Task { try await perform(reader, probe) }
        do {
            let outcome = try await task.value
            #expect(outcome == (race == .clipboard ? .clipboardChanged : .blocked))
            #expect(race != .cancellation)
        } catch is CancellationError { #expect(race == .cancellation) }
        #expect(probe.writes.isEmpty)
    }
    @Test(arguments: [false, true])
    func protectedOrExpiredOriginalCannotBeCopied(expired: Bool) async throws {
        var reader = RecipeDeliveryReader(beforeContent: {})
        if expired { reader.item.expiresAt = .distantPast } else { reader.item.isSensitive = true }
        let probe = RecipeClipboardProbe()
        #expect(try await perform(reader, probe) == .selectionChanged)
        #expect(probe.writes.isEmpty)
    }
    @Test func mutatedContentIsNeverDeliveredFromAnOldPreview() async throws {
        var reader = RecipeDeliveryReader(beforeContent: {})
        reader.content = "Replacement synthetic text"
        let probe = RecipeClipboardProbe()
        #expect(try await perform(reader, probe) == .selectionChanged)
        #expect(probe.writes.isEmpty)
    }
    private func perform(
        _ reader: RecipeDeliveryReader, _ probe: RecipeClipboardProbe
    ) async throws -> TextRecipeDelivery.Outcome {
        try await TextRecipeDelivery.copy(
            result: "Processed synthetic text",
            expected: CombinedTextPart(
                id: reader.item.id, content: .text("Reviewed synthetic text")),
            from: reader,
            clipboardUnchanged: { probe.unchanged },
            isAllowed: { probe.allowed },
            write: { probe.writes.append($0) })
    }
}
